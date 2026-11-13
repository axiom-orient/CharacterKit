import ReactiveCharacterKit
import SwiftUI

/// Demo choices are adapters to public SDK configurations; state remains host-owned.
enum CharacterDemoAppearance: String, CaseIterable, Identifiable {
  case semi, black, white, arcade, cat, catSimple, norwegianGIF
  case portrait, girl, flowerGirl, boy, cappedBoy, boyThreeQuarter

  var id: Self { self }

  var label: String {
    switch self {
    case .semi: "SEMI"
    case .black: "Black"
    case .white: "White"
    case .arcade: "Arcade"
    case .cat: "Cat"
    case .catSimple: "Cat · Simple"
    case .norwegianGIF: "Norwegian · Animated GIF"
    case .portrait: "Portrait"
    case .girl: "Girl"
    case .flowerGirl: "Girl · Flower"
    case .boy: "Boy"
    case .cappedBoy: "Boy · Cap"
    case .boyThreeQuarter: "Boy · Three-quarter"
    }
  }

  private var direction: CharacterArtDirection? {
    switch self {
    case .semi: .semiDocumentCat
    case .black: .black
    case .white: .white
    case .arcade: .arcade
    case .cat: .cat
    case .catSimple: .catSimple2D
    case .norwegianGIF: nil
    case .portrait: .portrait
    case .girl: CharacterPortraitStyle.bobGirl.artDirection
    case .flowerGirl: CharacterPortraitStyle.flowerGirl.artDirection
    case .boy: CharacterPortraitStyle.shortHairBoy.artDirection
    case .cappedBoy: CharacterPortraitStyle.cappedBoy.artDirection
    case .boyThreeQuarter: CharacterPortraitStyle.boy(viewpoint: .threeQuarterRight).artDirection
    }
  }

  @MainActor @ViewBuilder
  func view(state: CharacterState, playbackTrigger: Int, accessibilityLabel: String,
    accessibilityValue: String? = nil) -> some View {
    if let direction {
      ReactiveCharacterView(state: state, artDirection: direction,
        accessibilityLabel: accessibilityLabel, accessibilityValue: accessibilityValue)
    } else {
      ReactiveCharacterGIFView(state: state, playbackTrigger: playbackTrigger,
        accessibilityLabel: accessibilityLabel, accessibilityValue: accessibilityValue)
    }
  }
}
