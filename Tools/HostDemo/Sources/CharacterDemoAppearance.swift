import ReactiveCharacterKit

/// Demo choices are adapters to public SDK configurations; state remains host-owned.
enum CharacterDemoAppearance: String, CaseIterable, Identifiable {
  case semi, black, white, arcade, cat, catSimple, norwegianGIF, norwegianHero, norwegianWarm
  case norwegianSilver, norwegianCream, portrait, girl, flowerGirl, boy, cappedBoy, boyThreeQuarter

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
    case .norwegianHero: "Norwegian · Hero"
    case .norwegianWarm: "Norwegian · Warm"
    case .norwegianSilver: "Norwegian · Silver"
    case .norwegianCream: "Norwegian · Cream"
    case .portrait: "Portrait"
    case .girl: "Girl"
    case .flowerGirl: "Girl · Flower"
    case .boy: "Boy"
    case .cappedBoy: "Boy · Cap"
    case .boyThreeQuarter: "Boy · Three-quarter"
    }
  }

  var direction: CharacterArtDirection {
    switch self {
    case .semi: .semiDocumentCat
    case .black: .black
    case .white: .white
    case .arcade: .arcade
    case .cat: .cat
    case .catSimple: .catSimple2D
    case .norwegianGIF: .catNorwegianForest
    case .norwegianHero: .reference(.norwegianForest(.hero))
    case .norwegianWarm: .reference(.norwegianForest(.warmTabby))
    case .norwegianSilver: .reference(.norwegianForest(.silver))
    case .norwegianCream: .reference(.norwegianForest(.creamBrown))
    case .portrait: .portrait
    case .girl: CharacterPortraitStyle.bobGirl.artDirection
    case .flowerGirl: CharacterPortraitStyle.flowerGirl.artDirection
    case .boy: CharacterPortraitStyle.shortHairBoy.artDirection
    case .cappedBoy: CharacterPortraitStyle.cappedBoy.artDirection
    case .boyThreeQuarter: CharacterPortraitStyle.boy(viewpoint: .threeQuarterRight).artDirection
    }
  }
}
