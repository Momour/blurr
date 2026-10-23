import Foundation

/// Plan de masquage : pour chaque image analysée, la liste des ellipses à masquer, en coordonnées normalisées
/// (origine en haut à gauche, repère d'affichage). Portage fidèle de `MaskPlan.kt` (Android v0.2).
///
/// Construction (`build`) :
///  1. les détections sont reliées d'une image à l'autre en pistes (plus proche voisin, centre à environ une taille
///     de visage, davantage après un trou, taille comparable) ;
///  2. seules les pistes confirmées sont masquées : au moins une détection de score >= confirmThreshold et au moins
///     minHits détections. Les détections isolées de score moyen sont écartées ;
///  3. à l'intérieur d'une piste, les images sans détection (trou d'au plus maxGapUs) reçoivent une boîte interpolée ;
///  4. chaque piste est prolongée de marginFrames images avant et après ;
///  5. sur chaque image, la boîte d'une piste couvre aussi ses boîtes des images voisines (unionFrames), puis devient
///     une ellipse agrandie de maskScale.
public final class MaskPlan {

    /// Bilan du filtrage, pour le journal et l'écran de fin.
    public struct Stats: Equatable, Sendable {
        public let tracks: Int
        public let confirmedTracks: Int
        public let maskedFrames: Int
        public var rejectedTracks: Int { tracks - confirmedTracks }

        public init(tracks: Int, confirmedTracks: Int, maskedFrames: Int) {
            self.tracks = tracks
            self.confirmedTracks = confirmedTracks
            self.maskedFrames = maskedFrames
        }
    }

    public static let maxShiftUs: Int64 = 2_000_000
    public static let empty: [Float] = []

    /// Distance maximale entre deux centres d'une même piste, en tailles de visage : `gate` entre deux images
    /// proches, plus `gatePerS` par seconde écoulée (un visage peut se déplacer pendant un trou de détection).
    public static let gate: Float = 1.0
    public static let gatePerS: Float = 6.0

    /// Rapport de surfaces admis entre deux boîtes d'une même piste.
    public static let minAreaRatio: Float = 0.4
    public static let maxAreaRatio: Float = 2.5

    private let ptsUs: [Int64]
    /// Par image : [cx, cy, rx, ry, cx, cy, rx, ry, ...].
    private let ellipses: [[Float]]
    private let toleranceUs: Int64
    public let stats: Stats
    private var shiftUs: Int64 = 0

    private init(ptsUs: [Int64], ellipses: [[Float]], toleranceUs: Int64, stats: Stats) {
        self.ptsUs = ptsUs
        self.ellipses = ellipses
        self.toleranceUs = toleranceUs
        self.stats = stats
    }

    public var frameCount: Int { ptsUs.count }
    public var firstPtsUs: Int64 { ptsUs.first ?? 0 }

    /// Décalage appliqué entre l'horloge de l'export et celle de l'analyse (microsecondes).
    public var appliedShiftUs: Int64 { shiftUs }

    /// Horodatage de l'image analysée d'indice `index` (ordre de présentation).
    public func pts(at index: Int) -> Int64 { ptsUs[index] }

    /// Ellipses de l'image analysée d'indice `index`.
    public func ellipses(at index: Int) -> [Float] { ellipses[index] }

    /// Cale l'horloge de l'export sur celle de l'analyse à partir de la première image rendue.
    @discardableResult
    public func alignTo(_ firstExportPtsUs: Int64) -> Int64 {
        shiftUs = shiftFor(firstExportPtsUs)
        return shiftUs
    }

    /// Décalage qui cale une horloge dont la première image est à `firstPtsUs` sur celle de l'analyse.
    public func shiftFor(_ firstPtsUs: Int64) -> Int64 {
        guard let first = ptsUs.first else { return 0 }
        let shift = first - firstPtsUs
        return abs(shift) <= MaskPlan.maxShiftUs ? shift : 0
    }

    /// Ellipses à appliquer à l'image d'horodatage `exportPtsUs` ; tableau vide si aucune image analysée n'est assez
    /// proche.
    public func lookup(_ exportPtsUs: Int64) -> [Float] { lookupShifted(exportPtsUs, shift: shiftUs) }

    /// Comme `lookup`, avec un décalage explicite (contrôle du fichier produit, qui a sa propre horloge).
    public func lookupShifted(_ pts: Int64, shift: Int64) -> [Float] {
        if ptsUs.isEmpty { return MaskPlan.empty }
        let t = pts + shift
        var lo = 0
        var hi = ptsUs.count - 1
        while lo < hi {
            let mid = (lo + hi) >> 1
            if ptsUs[mid] < t { lo = mid + 1 } else { hi = mid }
        }
        var best = lo
        if lo > 0 && abs(ptsUs[lo - 1] - t) <= abs(ptsUs[lo] - t) { best = lo - 1 }
        return abs(ptsUs[best] - t) <= toleranceUs ? ellipses[best] : MaskPlan.empty
    }

    // ------------------------------------------------------------------ construction

    /// - Parameters:
    ///   - aspect: rapport largeur / hauteur de l'image affichée (les coordonnées sont normalisées séparément en x et
    ///     en y : il faut ce rapport pour mesurer des distances).
    ///   - unionFrames: la boîte d'une piste sur une image couvre aussi ses boîtes des `unionFrames` images voisines.
    public static func build(
        detections: Detections,
        params: TrackingParams,
        maskScale: Float,
        marginFrames: Int,
        aspect: Float = 1,
        unionFrames: Int = 1
    ) -> MaskPlan {
        let n = detections.size
        if n == 0 { return MaskPlan(ptsUs: [], ellipses: [], toleranceUs: 0, stats: Stats(tracks: 0, confirmedTracks: 0, maskedFrames: 0)) }

        // Ordre de présentation garanti (tri stable), même si la source a livré les images dans un autre ordre.
        let order = (0..<n).sorted { a, b in
            let ta = detections.ptsUs(a)
            let tb = detections.ptsUs(b)
            return ta != tb ? ta < tb : a < b
        }
        let times = order.map { detections.ptsUs($0) }
        let faces = order.map { detections.faces($0).filter { $0.score >= params.keepThreshold } }

        let tracks = track(times: times, faces: faces, maxGapUs: params.maxGapUs, aspect: aspect > 0 ? aspect : 1)
        let confirmed = tracks.filter { t in
            t.hits.count >= max(1, params.minHits) && t.hits.contains { $0.box.score >= params.confirmThreshold }
        }

        // Boîtes par image et par piste (interpolation dans les trous, marge aux extrémités).
        let spans = confirmed.map { boxesOf($0, times: times, margin: max(0, marginFrames)) }
        let u = max(0, unionFrames)
        var merged = [[Float]](repeating: [], count: n)
        for span in spans {
            for i in stride(from: max(0, span.start - u), through: min(n - 1, span.end + u), by: 1) {
                guard let union = span.unionAround(i, u) else { continue }
                let box = FaceBox(x: union[0], y: union[1], w: union[2] - union[0], h: union[3] - union[1], score: 1)
                merged[i].append(contentsOf: ellipse(of: box, scale: maskScale))
            }
        }
        let stats = Stats(
            tracks: tracks.count,
            confirmedTracks: confirmed.count,
            maskedFrames: merged.reduce(0) { $0 + ($1.isEmpty ? 0 : 1) }
        )
        return MaskPlan(ptsUs: times, ellipses: merged, toleranceUs: toleranceFor(times), stats: stats)
    }

    /// Ellipse centrée sur la boîte, de demi-axes (w, h) x scale / 2 : couvre la boîte d'origine à 100 % pour
    /// scale >= 1,42.
    public static func ellipse(of box: FaceBox, scale: Float) -> [Float] {
        [box.x + box.w / 2, box.y + box.h / 2, box.w * scale / 2, box.h * scale / 2]
    }

    // ------------------------------------------------------------------ suivi

    public struct Hit {
        public let frame: Int
        public let box: FaceBox
    }

    public final class Track {
        public var hits: [Hit] = []
        public var last: Hit { hits[hits.count - 1] }
    }

    /// Relie les détections en pistes, image par image, par appariement glouton du plus proche voisin.
    public static func track(times: [Int64], faces: [[FaceBox]], maxGapUs: Int64, aspect: Float) -> [Track] {
        var all: [Track] = []
        var active: [Track] = []
        for i in times.indices {
            active.removeAll { times[i] - times[$0.last.frame] > maxGapUs }
            let dets = faces[i]
            if dets.isEmpty { continue }

            // (distance, piste, détection, rang d'insertion pour un tri stable)
            var pairs: [(dist: Float, track: Int, det: Int, rank: Int)] = []
            for (ti, t) in active.enumerated() {
                let b = t.last.box
                let gate = MaskPlan.gate + MaskPlan.gatePerS * Float(times[i] - times[t.last.frame]) / 1_000_000
                for (di, d) in dets.enumerated() {
                    let dist = distance(b, d, aspect: aspect)
                    let ratio = (d.w * d.h) / (b.w * b.h)
                    if dist <= gate && ratio >= MaskPlan.minAreaRatio && ratio <= MaskPlan.maxAreaRatio {
                        pairs.append((dist, ti, di, pairs.count))
                    }
                }
            }
            pairs.sort { $0.dist != $1.dist ? $0.dist < $1.dist : $0.rank < $1.rank }
            var usedTracks = [Bool](repeating: false, count: active.count)
            var usedDets = [Bool](repeating: false, count: dets.count)
            for p in pairs {
                if usedTracks[p.track] || usedDets[p.det] { continue }
                usedTracks[p.track] = true
                usedDets[p.det] = true
                active[p.track].hits.append(Hit(frame: i, box: dets[p.det]))
            }
            for (di, d) in dets.enumerated() where !usedDets[di] {
                let t = Track()
                t.hits.append(Hit(frame: i, box: d))
                all.append(t)
                active.append(t)
            }
        }
        return all
    }

    /// Distance entre centres rapportée à la taille moyenne des deux boîtes (unités proportionnelles aux pixels).
    public static func distance(_ a: FaceBox, _ b: FaceBox, aspect: Float) -> Float {
        let dx = ((a.x + a.w / 2) - (b.x + b.w / 2)) * aspect
        let dy = (a.y + a.h / 2) - (b.y + b.h / 2)
        let size = ((a.w * aspect + a.h) / 2 + (b.w * aspect + b.h) / 2) / 2
        return size > 0 ? hypotf(dx, dy) / size : Float.greatestFiniteMagnitude
    }

    /// Boîtes [x0, y0, x1, y1] d'une piste, des images `start` à `end` incluses (nil : pas de boîte).
    struct Span {
        let start: Int
        let end: Int
        let boxes: [[Float]?]

        func at(_ frame: Int) -> [Float]? { frame >= start && frame <= end ? boxes[frame - start] : nil }

        /// Boîte englobant les boîtes des images `frame` - `u` à `frame` + `u` ; nil si aucune.
        func unionAround(_ frame: Int, _ u: Int) -> [Float]? {
            var out: [Float]? = nil
            for j in (frame - u)...(frame + u) {
                guard let b = at(j) else { continue }
                if var o = out {
                    o[0] = min(o[0], b[0]); o[1] = min(o[1], b[1])
                    o[2] = max(o[2], b[2]); o[3] = max(o[3], b[3])
                    out = o
                } else {
                    out = b
                }
            }
            return out
        }
    }

    static func boxesOf(_ t: Track, times: [Int64], margin: Int) -> Span {
        let n = times.count
        let hits = t.hits
        let first = hits[0]
        let last = t.last
        let start = max(0, first.frame - margin)
        let end = min(n - 1, last.frame + margin)
        var out = [[Float]?](repeating: nil, count: end - start + 1)
        func corners(_ b: FaceBox) -> [Float] { [b.x, b.y, b.x + b.w, b.y + b.h] }
        if hits.count > 1 {
            for k in 0..<(hits.count - 1) {
                let a = hits[k]
                let b = hits[k + 1]
                let ca = corners(a.box)
                let cb = corners(b.box)
                let span = Float(times[b.frame] - times[a.frame])
                for f in a.frame..<b.frame {
                    let w: Float = span > 0 ? Float(times[f] - times[a.frame]) / span : 0
                    out[f - start] = (0..<4).map { ca[$0] + (cb[$0] - ca[$0]) * w }
                }
            }
        }
        out[last.frame - start] = corners(last.box)
        for f in stride(from: start, to: first.frame, by: 1) { out[f - start] = corners(first.box) }
        for f in stride(from: last.frame + 1, through: end, by: 1) { out[f - start] = corners(last.box) }
        return Span(start: start, end: end, boxes: out)
    }

    static func toleranceFor(_ times: [Int64]) -> Int64 {
        if times.count < 2 { return 200_000 }
        var diffs = (0..<(times.count - 1)).map { times[$0 + 1] - times[$0] }
        diffs.sort()
        let median = diffs[diffs.count / 2]
        return max(120_000, (median * 5) / 2)
    }
}
