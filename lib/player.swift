// Lecteur d'encoche de `siri -i`.
//
// Lit une suite de fragments audio (chunk_000.caf, chunk_001.caf, …) déposés
// dans un dossier au fil de la synthèse : la lecture démarre dès le premier
// fragment au lieu d'attendre les ~6 minutes que demande un long PDF.
// Le fichier `.done` signale que la synthèse est terminée.
//
// S'inscrit dans « En cours de lecture » de macOS (Centre de contrôle et
// touches média du clavier) et dessine son propre panneau sous l'encoche.
// Le dossier de fragments lui appartient : il l'efface en partant, quelle que
// soit la manière dont il s'arrête.
import AVFoundation
import Cocoa
import MediaPlayer

// ---------------------------------------------------------------- arguments
let a = CommandLine.arguments
guard a.count >= 4 else {
    FileHandle.standardError.write(Data("usage: player <dossier> <titre> <durée estimée>\n".utf8))
    exit(2)
}
let dossier = URL(fileURLWithPath: a[1])
let titre = a[2]
let dureeEstimee = Double(a[3]) ?? 0
let vitesseInitiale = a.count > 4 ? (Double(a[4]) ?? 0) : 0

/// Pas des boutons de recul et d'avance, en secondes.
let SAUT: Double = 5

/// L'écran intégré, pas l'écran actif : `NSScreen.main` désigne celui qui a le
/// focus, et pour une app d'arrière-plan avec un moniteur externe branché il
/// renvoie le mauvais. On prend celui qui a une encoche.
func ecranEncoche() -> NSScreen {
    NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.screens[0]
}

// ------------------------------------------------------------------ lecture
final class Lecture {
    let file = AVQueuePlayer()
    private var durees: [Double] = []      // durée de chaque fragment mis en file
    private var urls: [URL] = []
    private var jouees = 0                 // fragments entièrement consommés
    private(set) var prochain = 0          // index du prochain fragment à chercher
    private(set) var complet = false       // le fichier .done est apparu
    private(set) var arrivee = false       // lecture terminée : on reste ouvert
    private var fige: Double? = nil        // position affichée une fois arrivé

    static let vitesses: [Double] = [0.75, 1.0, 1.25, 1.5, 1.75, 2.0]
    /// Multiplicateur de lecture, retenu d'une lecture à l'autre.
    var vitesse: Double = {
        let v = UserDefaults.standard.double(forKey: "siri-say.vitesse")
        return Lecture.vitesses.contains(v) ? v : 1.0
    }() {
        didSet {
            UserDefaults.standard.set(vitesse, forKey: "siri-say.vitesse")
            if enLecture { file.rate = Float(vitesse) }
        }
    }
    /// Démarre à la vitesse choisie : `play()` remettrait le multiplicateur à 1.
    func demarre() { file.rate = Float(vitesse) }

    func vitesseSuivante() {
        let i = Lecture.vitesses.firstIndex(of: vitesse) ?? 1
        vitesse = Lecture.vitesses[(i + 1) % Lecture.vitesses.count]
    }

    /// `.timeDomain` garde la voix naturelle quand on accélère ; sans lui,
    /// le timbre monte comme une bande passée en avance rapide.
    private func morceau(_ u: URL) -> AVPlayerItem {
        let i = AVPlayerItem(url: u)
        i.audioTimePitchAlgorithm = .timeDomain
        return i
    }

    var totalReel: Double { durees.reduce(0, +) }
    var duree: Double { complet ? totalReel : max(dureeEstimee, totalReel) }
    var enLecture: Bool { file.rate > 0 }
    /// Fin de ce qui est réellement disponible : on ne peut pas viser au-delà.
    var disponible: Double { totalReel }

    var ecoule: Double {
        if let f = fige { return f }
        let avant = durees.prefix(jouees).reduce(0, +)
        let courant = file.currentItem?.currentTime().seconds ?? 0
        return avant + (courant.isFinite ? courant : 0)
    }

    init() {
        file.actionAtItemEnd = .advance
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main
        ) { [weak self] _ in self?.jouees += 1 }
    }

    /// Met en file les fragments nouvellement écrits.
    func ramasse() {
        let fm = FileManager.default
        while true {
            let f = dossier.appendingPathComponent(String(format: "chunk_%03d.caf", prochain))
            guard fm.fileExists(atPath: f.path) else { break }
            let asset = AVURLAsset(url: f)
            let d = CMTimeGetSeconds(asset.duration)
            durees.append(d.isFinite ? d : 0)
            urls.append(f)
            file.insert(morceau(f), after: nil)
            prochain += 1
        }
        if fm.fileExists(atPath: dossier.appendingPathComponent(".done").path) { complet = true }
    }

    /// Vrai quand tout a été joué. On ne quitte pas pour autant : le panneau
    /// reste en place, prêt à relire.
    var fini: Bool { complet && file.items().isEmpty }

    private func reconstruit(depuis i: Int) {
        file.removeAllItems()
        for k in i..<urls.count { file.insert(morceau(urls[k]), after: nil) }
        jouees = i
    }

    /// Fin de la file : on remet tout en place, en pause, au lieu de fermer.
    func arrive() {
        guard !arrivee else { return }
        arrivee = true
        fige = totalReel
        reconstruit(depuis: 0)
        file.pause()
    }

    func bascule() {
        if arrivee { vise(0); demarre(); return }   // relire depuis le début
        enLecture ? file.pause() : demarre()
    }

    /// Vise une position absolue, fragments confondus.
    ///
    /// AVQueuePlayer ne sait pas viser au-delà de l'élément courant : on
    /// reconstruit donc la file à partir du fragment qui contient la cible.
    func vise(_ global: Double) {
        guard !durees.isEmpty else { return }
        arrivee = false
        fige = nil
        let cible = min(max(0, global), max(0, disponible - 0.3))
        var i = 0, debut = 0.0
        while i < durees.count - 1, debut + durees[i] <= cible {
            debut += durees[i]; i += 1
        }
        let dedans = cible - debut
        let jouait = enLecture

        if i == jouees, let item = file.currentItem {
            item.seek(to: CMTime(seconds: dedans, preferredTimescale: 600),
                      toleranceBefore: .zero, toleranceAfter: .zero, completionHandler: nil)
        } else {
            reconstruit(depuis: i)
            file.currentItem?.seek(to: CMTime(seconds: dedans, preferredTimescale: 600),
                                   toleranceBefore: .zero, toleranceAfter: .zero,
                                   completionHandler: nil)
        }
        if jouait { demarre() }
    }

    func decale(_ s: Double) { vise(ecoule + s) }
}

let lecture = Lecture()

// ------------------------------------------------------------------- ménage
var menageFait = false
func termine() {
    guard !menageFait else { return }
    menageFait = true
    lecture.file.pause()
    MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    // Le dossier de fragments appartient à ce processus : il part avec lui.
    try? FileManager.default.removeItem(at: dossier)
    NSApplication.shared.terminate(nil)
    exit(0)
}
for sig in [SIGINT, SIGTERM, SIGHUP] { signal(sig) { _ in termine() } }

// ------------------------------------------------- « En cours de lecture »
let centre = MPNowPlayingInfoCenter.default()
func majSysteme() {
    centre.nowPlayingInfo = [
        MPMediaItemPropertyTitle: titre,
        MPMediaItemPropertyArtist: "siri",
        MPMediaItemPropertyAlbumTitle: "Lecture à voix haute",
        MPMediaItemPropertyPlaybackDuration: lecture.duree,
        MPNowPlayingInfoPropertyElapsedPlaybackTime: lecture.ecoule,
        MPNowPlayingInfoPropertyPlaybackRate: lecture.enLecture ? lecture.vitesse : 0.0,
    ]
    centre.playbackState = lecture.enLecture ? .playing : .paused
}

let commandes = MPRemoteCommandCenter.shared()
for c in [commandes.playCommand, commandes.pauseCommand, commandes.togglePlayPauseCommand,
          commandes.skipForwardCommand, commandes.skipBackwardCommand] { c.isEnabled = true }
commandes.skipForwardCommand.preferredIntervals = [NSNumber(value: SAUT)]
commandes.skipBackwardCommand.preferredIntervals = [NSNumber(value: SAUT)]
commandes.playCommand.addTarget { _ in lecture.demarre(); majSysteme(); return .success }
commandes.pauseCommand.addTarget { _ in lecture.file.pause(); majSysteme(); return .success }
commandes.togglePlayPauseCommand.addTarget { _ in lecture.bascule(); majSysteme(); return .success }
commandes.skipForwardCommand.addTarget { _ in lecture.decale(SAUT); majSysteme(); return .success }
commandes.skipBackwardCommand.addTarget { _ in lecture.decale(-SAUT); majSysteme(); return .success }

// ------------------------------------------------------------------ panneau
func mmss(_ s: Double) -> String {
    guard s.isFinite, s >= 0 else { return "--:--" }
    let t = Int(s.rounded())
    return String(format: "%d:%02d", t / 60, t % 60)
}

final class Panneau: NSView {
    static let replie = NSSize(width: 270, height: 32)   // 185 d'encoche + 42 visibles de chaque côté
    static let ouvert = NSSize(width: 340, height: 156)

    var deplie = false
    let ondes = OndeView()
    let titreL = NSTextField(labelWithString: "")
    let sousL = NSTextField(labelWithString: "")
    let ecouleL = NSTextField(labelWithString: "0:00")
    let restantL = NSTextField(labelWithString: "--:--")
    let barreFond = NSView(), barreDispo = NSView(), barreJauge = NSView()
    let pouce = NSView()
    let bPause = NSButton(), bAvant = NSButton(), bArriere = NSButton(), bQuitter = NSButton()
    let bVitesse = NSButton()

    var onBascule: (() -> Void)?
    var onDecale: ((Double) -> Void)?
    var onVise: ((Double) -> Void)?       // fraction 0…1 de la durée
    var onQuitter: (() -> Void)?
    var onVitesse: (() -> Void)?
    var glisse = false

    override init(frame f: NSRect) {
        super.init(frame: f)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.cornerRadius = 14
        layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        addSubview(ondes)

        func label(_ l: NSTextField, _ t: CGFloat, _ p: NSFont.Weight, _ al: CGFloat) {
            l.font = .systemFont(ofSize: t, weight: p)
            l.textColor = NSColor.white.withAlphaComponent(al)
            l.lineBreakMode = .byTruncatingTail
            l.isHidden = true
            addSubview(l)
        }
        label(titreL, 13, .semibold, 1.0)
        label(sousL, 11, .regular, 0.55)
        label(ecouleL, 10, .regular, 0.5)
        label(restantL, 10, .regular, 0.5)
        restantL.alignment = .right

        func bloc(_ v: NSView, _ c: NSColor, _ r: CGFloat) {
            v.wantsLayer = true
            v.layer?.backgroundColor = c.cgColor
            v.layer?.cornerRadius = r
            v.isHidden = true
            addSubview(v)
        }
        let ocre = NSColor(calibratedRed: 0.894, green: 0.702, blue: 0.388, alpha: 1)
        bloc(barreFond, NSColor.white.withAlphaComponent(0.16), 2)
        bloc(barreDispo, NSColor.white.withAlphaComponent(0.30), 2)   // déjà synthétisé
        bloc(barreJauge, ocre, 2)
        bloc(pouce, .white, 5)

        func bouton(_ b: NSButton, _ sym: String, _ desc: String, _ t: CGFloat, _ sel: Selector) {
            b.isBordered = false
            b.bezelStyle = .regularSquare
            b.imagePosition = .imageOnly
            b.image = NSImage(systemSymbolName: sym, accessibilityDescription: desc)?
                .withSymbolConfiguration(.init(pointSize: t, weight: .medium))
            b.contentTintColor = .white
            b.toolTip = desc
            b.isHidden = true
            b.target = self
            b.action = sel
            addSubview(b)
        }
        bouton(bArriere, "gobackward.5", "Reculer de 5 secondes", 15, #selector(reculer))
        bouton(bPause, "pause.fill", "Pause", 21, #selector(basculer))
        bouton(bAvant, "goforward.5", "Avancer de 5 secondes", 15, #selector(avancer))
        bouton(bQuitter, "xmark", "Fermer et arrêter la lecture", 11, #selector(quitter))
        bQuitter.contentTintColor = NSColor.white.withAlphaComponent(0.55)

        bVitesse.isBordered = false
        bVitesse.bezelStyle = .regularSquare
        bVitesse.toolTip = "Vitesse de lecture"
        bVitesse.isHidden = true
        bVitesse.target = self
        bVitesse.action = #selector(changeVitesse)
        addSubview(bVitesse)
    }
    required init?(coder: NSCoder) { fatalError() }

    @objc func basculer() { onBascule?() }
    @objc func avancer() { onDecale?(SAUT) }
    @objc func reculer() { onDecale?(-SAUT) }
    @objc func quitter() { onQuitter?() }
    @objc func changeVitesse() { onVitesse?() }

    // ------------------------------------------------- viser sur la ligne
    /// Bande de saisie généreuse autour de la barre : 4 pt de haut seraient
    /// impossibles à viser à la souris.
    var zoneBarre: NSRect {
        NSRect(x: 17, y: yBarre - 11, width: bounds.width - 34, height: 26)
    }
    private var yBarre: CGFloat { bounds.height - 46 - 54 }

    override func mouseDown(with e: NSEvent) {
        let p = convert(e.locationInWindow, from: nil)
        guard deplie, zoneBarre.contains(p) else { return }
        glisse = true
        viseDepuis(p)
    }
    override func mouseDragged(with e: NSEvent) {
        guard glisse else { return }
        viseDepuis(convert(e.locationInWindow, from: nil))
    }
    override func mouseUp(with e: NSEvent) { glisse = false }

    private func viseDepuis(_ p: NSPoint) {
        let l = bounds.width - 34
        onVise?(min(1, max(0, (p.x - 17) / l)))
    }

    override func resetCursorRects() {
        if deplie { addCursorRect(zoneBarre, cursor: .pointingHand) }
    }

    // ------------------------------------------------------------ montage
    func montre(_ ouvrir: Bool) {
        guard ouvrir != deplie else { return }
        deplie = ouvrir
        let taille = ouvrir ? Panneau.ouvert : Panneau.replie
        if let w = window {
            let e = ecranEncoche()
            let cadre = NSRect(x: e.frame.midX - taille.width / 2,
                               y: e.frame.maxY - taille.height,
                               width: taille.width, height: taille.height)
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.26
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                w.animator().setFrame(cadre, display: true)
            }
        }
        for v in [titreL, sousL, ecouleL, restantL, barreFond, barreDispo, barreJauge, pouce] {
            v.isHidden = !ouvrir
        }
        for b in [bPause, bAvant, bArriere, bQuitter, bVitesse] { b.isHidden = !ouvrir }
        ondes.isHidden = ouvrir
        layer?.cornerRadius = ouvrir ? 22 : 14
        if !ouvrir { glisse = false }
        window?.invalidateCursorRects(for: self)
        needsLayout = true
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        let l = bounds.width, h = bounds.height
        guard deplie else {
            ondes.frame = NSRect(x: 9, y: h / 2 - 6, width: 26, height: 12)
            return
        }
        // 46 pt de marge haute : les 32 premiers points sont sous l'encoche.
        let haut = h - 46
        titreL.frame = NSRect(x: 66, y: haut - 16, width: l - 66 - 38, height: 17)
        sousL.frame = NSRect(x: 66, y: haut - 32, width: l - 66 - 38, height: 15)
        bQuitter.frame = NSRect(x: l - 32, y: haut - 17, width: 20, height: 20)

        let yb = yBarre
        barreFond.frame = NSRect(x: 17, y: yb, width: l - 34, height: 4)
        barreDispo.frame = NSRect(x: 17, y: yb, width: 0, height: 4)
        barreJauge.frame = NSRect(x: 17, y: yb, width: 0, height: 4)
        pouce.frame = NSRect(x: 17 - 5, y: yb - 3, width: 10, height: 10)
        ecouleL.frame = NSRect(x: 17, y: yb - 18, width: 70, height: 13)
        restantL.frame = NSRect(x: l - 87, y: yb - 18, width: 70, height: 13)

        let yBoutons = yb - 48
        bVitesse.frame = NSRect(x: l - 17 - 44, y: yBoutons + 3, width: 44, height: 20)
        bArriere.frame = NSRect(x: l / 2 - 56, y: yBoutons, width: 26, height: 26)
        bPause.frame = NSRect(x: l / 2 - 14, y: yBoutons - 1, width: 28, height: 28)
        bAvant.frame = NSRect(x: l / 2 + 30, y: yBoutons, width: 26, height: 26)
    }

    var fraction: CGFloat = 0     // progression, pour l'anneau du mode replié

    override func draw(_ r: NSRect) {
        NSColor.black.setFill()
        bounds.fill()
        guard deplie else {
            // Anneau de progression, à DROITE de l'encoche.
            let d: CGFloat = 13
            let c = NSPoint(x: bounds.width - 9 - d / 2, y: bounds.midY)
            let f = NSBezierPath()
            f.appendArc(withCenter: c, radius: d / 2, startAngle: 0, endAngle: 360)
            f.lineWidth = 2.2
            NSColor.white.withAlphaComponent(0.22).setStroke()
            f.stroke()
            if fraction > 0 {
                let j = NSBezierPath()
                j.appendArc(withCenter: c, radius: d / 2, startAngle: 90,
                            endAngle: 90 - 360 * Double(min(1, fraction)), clockwise: true)
                j.lineWidth = 2.2
                j.lineCapStyle = .round
                NSColor(calibratedRed: 0.894, green: 0.702, blue: 0.388, alpha: 1).setStroke()
                j.stroke()
            }
            return
        }
        let p = NSRect(x: 17, y: bounds.height - 46 - 40, width: 40, height: 40)
        let chemin = NSBezierPath(roundedRect: p, xRadius: 8, yRadius: 8)
        NSGradient(starting: NSColor(calibratedRed: 0.773, green: 0.561, blue: 0.196, alpha: 1),
                   ending: NSColor(calibratedRed: 0.486, green: 0.310, blue: 0.165, alpha: 1))?
            .draw(in: chemin, angle: -60)
        if !bVitesse.isHidden {
            let f = bVitesse.frame
            NSColor.white.withAlphaComponent(0.13).setFill()
            NSBezierPath(roundedRect: f, xRadius: f.height / 2, yRadius: f.height / 2).fill()
        }
        let s = "¶" as NSString
        let at: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 17, weight: .bold),
            .foregroundColor: NSColor.white.withAlphaComponent(0.94)]
        let t = s.size(withAttributes: at)
        s.draw(at: NSPoint(x: p.midX - t.width / 2, y: p.midY - t.height / 2), withAttributes: at)
    }

    func rafraichis(titre: String, sous: String, ecoule: Double, duree: Double,
                    dispo: Double, joue: Bool, vitesse: Double) {
        ondes.joue = joue
        guard deplie else {
            fraction = duree > 0 ? CGFloat(min(1, max(0, ecoule / duree))) : 0
            needsDisplay = true
            return
        }
        titreL.stringValue = titre
        sousL.stringValue = sous
        ecouleL.stringValue = mmss(ecoule)
        restantL.stringValue = duree > 0 ? "−" + mmss(max(0, duree - ecoule)) : "--:--"
        let l = bounds.width - 34
        let part = duree > 0 ? min(1, max(0, ecoule / duree)) : 0
        let partDispo = duree > 0 ? min(1, max(0, dispo / duree)) : 0
        barreJauge.frame.size.width = l * CGFloat(part)
        barreDispo.frame.size.width = l * CGFloat(partDispo)
        pouce.frame.origin.x = 17 + l * CGFloat(part) - 5
        let libelle = String(format: "%.2f", vitesse)
            .replacingOccurrences(of: ".", with: ",")
            .replacingOccurrences(of: ",00", with: "") + "×"
        bVitesse.attributedTitle = NSAttributedString(string: libelle, attributes: [
            .font: NSFont.systemFont(ofSize: 10.5, weight: .semibold),
            .foregroundColor: NSColor.white.withAlphaComponent(0.85),
            .paragraphStyle: { let s = NSMutableParagraphStyle(); s.alignment = .center; return s }()])
        bPause.image = NSImage(systemSymbolName: joue ? "pause.fill" : "play.fill",
                               accessibilityDescription: joue ? "Pause" : "Reprendre")?
            .withSymbolConfiguration(.init(pointSize: 21, weight: .medium))
        ondes.joue = joue
    }
}

/// Six barres animées, visibles quand le panneau est replié.
final class OndeView: NSView {
    var joue = true
    private var phase: CGFloat = 0
    override func viewDidMoveToWindow() {
        Timer.scheduledTimer(withTimeInterval: 1.0 / 20, repeats: true) { [weak self] _ in
            guard let s = self, !s.isHidden, s.joue else { return }
            s.phase += 0.16; s.needsDisplay = true
        }
    }
    override func draw(_ r: NSRect) {
        NSColor(calibratedRed: 0.894, green: 0.702, blue: 0.388, alpha: 1).setFill()
        for i in 0..<6 {
            let f = joue ? (sin(phase + CGFloat(i) * 0.9) + 1) / 2 : 0.25
            let h = bounds.height * (0.26 + 0.74 * f)
            NSBezierPath(roundedRect: NSRect(x: CGFloat(i) * 4.4, y: bounds.midY - h / 2,
                                             width: 2.2, height: h),
                         xRadius: 1.1, yRadius: 1.1).fill()
        }
    }
}

// -------------------------------------------------------------------- fenêtre
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let ecran = ecranEncoche()
let cadre = NSRect(x: ecran.frame.midX - Panneau.replie.width / 2,
                   y: ecran.frame.maxY - Panneau.replie.height,
                   width: Panneau.replie.width, height: Panneau.replie.height)
let fenetre = NSPanel(contentRect: cadre, styleMask: [.borderless, .nonactivatingPanel],
                      backing: .buffered, defer: false)
fenetre.isOpaque = false
fenetre.backgroundColor = .clear
fenetre.hasShadow = false
fenetre.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)
fenetre.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

let panneau = Panneau(frame: NSRect(origin: .zero, size: Panneau.replie))
panneau.autoresizingMask = [.width, .height]
fenetre.contentView = panneau
fenetre.orderFrontRegardless()

panneau.onBascule = { lecture.bascule(); majSysteme() }
panneau.onDecale = { lecture.decale($0); majSysteme() }
panneau.onVise = { f in lecture.vise(f * lecture.duree); majSysteme() }
panneau.onQuitter = { termine() }
panneau.onVitesse = { lecture.vitesseSuivante(); majSysteme() }

// ------------------------------------------------------- survol de la souris
// Suivi direct de la position du curseur plutôt qu'un NSTrackingArea : la zone
// de suivi se recalcule pendant l'animation de la fenêtre, et sur la partie
// droite du panneau elle est doublée par les réglages de la barre des menus,
// qui captaient l'événement avant nous.
func rectReplie() -> NSRect {
    let e = ecranEncoche()
    return NSRect(x: e.frame.midX - Panneau.replie.width / 2,
                  y: e.frame.maxY - Panneau.replie.height,
                  width: Panneau.replie.width, height: Panneau.replie.height)
}
func rectOuvert() -> NSRect {
    let e = ecranEncoche()
    return NSRect(x: e.frame.midX - Panneau.ouvert.width / 2,
                  y: e.frame.maxY - Panneau.ouvert.height,
                  width: Panneau.ouvert.width, height: Panneau.ouvert.height)
}

Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { _ in
    let souris = NSEvent.mouseLocation
    if panneau.deplie {
        // On ne referme pas tant qu'un glissement sur la ligne est en cours.
        if !panneau.glisse && !rectOuvert().insetBy(dx: -4, dy: -4).contains(souris) {
            panneau.montre(false)
        }
    } else if rectReplie().contains(souris) {
        panneau.montre(true)
    }
}

// -------------------------------------------------------------------- boucle
lecture.ramasse()
if vitesseInitiale > 0 { lecture.vitesse = vitesseInitiale }
lecture.demarre()
majSysteme()

var tics = 0
Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
    lecture.ramasse()
    tics += 1
    let sous: String
    if lecture.arrivee            { sous = "Lecture terminée · relire" }
    else if lecture.complet       { sous = "Voix 1" }
    else                          { sous = "Voix 1 · synthèse en cours (\(lecture.prochain) fragments)" }
    panneau.rafraichis(titre: titre, sous: sous, ecoule: lecture.ecoule,
                       duree: lecture.duree, dispo: lecture.disponible,
                       joue: lecture.enLecture, vitesse: lecture.vitesse)
    if tics % 2 == 0 { majSysteme() }
    // Arrivé au bout : on garde le panneau et les fragments. Seules la croix
    // et `siri -q` ferment l'application.
    if lecture.fini { lecture.arrive(); majSysteme() }
}

app.run()
