// Doit rester interprété par `swift` : un binaire compilé, même signé,
// se voit masquer les voix Siri par le système.
import AVFoundation
import Foundation

func voixSiri() -> [AVSpeechSynthesisVoice] {
    AVSpeechSynthesisVoice.speechVoices()
        .filter { $0.identifier.lowercased().contains("siri") }
        .sorted { $0.language < $1.language }
}

let args = CommandLine.arguments

if args.count > 1 && args[1] == "--list" {
    let v = voixSiri()
    if v.isEmpty {
        print("Aucune voix Siri disponible.")
        print("Réglages Système > Accessibilité > Contenu énoncé > Voix du système.")
    } else {
        for x in v { print("\(x.language)\t\(x.name)\t\(x.identifier)") }
    }
    exit(0)
}

guard args.count >= 4 else {
    FileHandle.standardError.write(Data("usage: tts.swift <voix> <débit> <sortie|-> < texte\n".utf8))
    exit(2)
}
let idVoix = args[1]
let debit = Float(args[2]) ?? AVSpeechUtteranceDefaultSpeechRate
let sortie = args[3]

let texte = String(data: FileHandle.standardInput.readDataToEndOfFile(), encoding: .utf8) ?? ""
guard !texte.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
    FileHandle.standardError.write(Data("siri-say : rien à lire.\n".utf8))
    exit(1)
}

var voix = AVSpeechSynthesisVoice(identifier: idVoix)
if voix == nil { voix = voixSiri().first }
guard let v = voix else {
    FileHandle.standardError.write(Data("siri-say : voix « \(idVoix) » introuvable. Essayez --list-voices.\n".utf8))
    exit(1)
}

// Découpe en paragraphes : la lecture démarre au premier, et Ctrl-C
// coupe proprement au lieu d'attendre la synthèse du document entier.
let blocs = texte.components(separatedBy: "\n\n")
    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    .filter { !$0.isEmpty }

let synth = AVSpeechSynthesizer()

func enonce(_ s: String) -> AVSpeechUtterance {
    let u = AVSpeechUtterance(string: s)
    u.voice = v
    u.rate = debit
    u.postUtteranceDelay = 0.25
    return u
}

if sortie == "-" {
    final class Suivi: NSObject, AVSpeechSynthesizerDelegate {
        let total: Int
        var termines = 0
        init(total: Int) { self.total = total }
        var fini: Bool { termines >= total }
        func speechSynthesizer(_ s: AVSpeechSynthesizer,
                               didFinish u: AVSpeechUtterance) { termines += 1 }
        func speechSynthesizer(_ s: AVSpeechSynthesizer,
                               didCancel u: AVSpeechUtterance) { termines += 1 }
    }
    let suivi = Suivi(total: blocs.count)
    synth.delegate = suivi
    signal(SIGINT) { _ in exit(130) }
    for b in blocs { synth.speak(enonce(b)) }
    while !suivi.fini {
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.1))
    }
} else {
    var fichier: AVAudioFile?
    var restants = blocs.count
    var frames: AVAudioFramePosition = 0
    for b in blocs {
        var fini = false
        synth.write(enonce(b)) { buffer in
            guard let pcm = buffer as? AVAudioPCMBuffer else { return }
            if pcm.frameLength == 0 { fini = true; return }
            if fichier == nil {
                fichier = try? AVAudioFile(forWriting: URL(fileURLWithPath: sortie),
                                           settings: pcm.format.settings)
            }
            try? fichier?.write(from: pcm)
            frames += AVAudioFramePosition(pcm.frameLength)
        }
        let limite = Date().addingTimeInterval(300)
        while !fini && Date() < limite {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        restants -= 1
    }
    fichier = nil
    if frames == 0 {
        FileHandle.standardError.write(Data("siri-say : aucun audio produit.\n".utf8))
        exit(1)
    }
}
