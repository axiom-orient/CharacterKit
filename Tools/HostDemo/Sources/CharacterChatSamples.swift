import ReactiveCharacterKit

struct CharacterChatSample: Identifiable {
  let emotion: CharacterEmotion
  let title: String
  let text: String
  var id: CharacterEmotion { emotion }
  static let all: [Self] = [
    .init(emotion: .joy, title: "기쁨", text: "오늘 정말 행복해요! 우리 함께 즐겁게 이야기해요."),
    .init(emotion: .affection, title: "애정", text: "사랑해요. 오늘도 당신을 보고 싶었어요."),
    .init(emotion: .gratitude, title: "감사", text: "정말 고마워요. 도와주신 덕분에 잘 해결했어요."),
    .init(emotion: .interest, title: "관심", text: "정말 궁금해요. 어떻게 하는지 자세히 알려 주세요?"),
    .init(emotion: .surprise, title: "놀람", text: "깜짝 놀랐어요! 세상에, 이런 일이 있다니요!"),
    .init(emotion: .calmTrust, title: "신뢰", text: "괜찮아요. 당신을 믿어요. 천천히 함께 해봐요."),
    .init(emotion: .sadness, title: "슬픔", text: "오늘은 조금 슬퍼요. 속상해서 눈물이 날 것 같아요."),
    .init(emotion: .anxietyFear, title: "불안", text: "조금 걱정돼요. 긴장되지만 함께 해 주세요."),
    .init(emotion: .angerIrritation, title: "화남", text: "정말 화가 나요! 왜 약속을 지키지 않았나요?"),
    .init(emotion: .disgustContempt, title: "불쾌", text: "이건 정말 싫어요. 기분이 조금 불쾌해요."),
    .init(emotion: .shameGuilt, title: "부끄러움", text: "정말 미안해요. 제가 실수해서 부끄러워요."),
    .init(emotion: .fatigueBurden, title: "피곤함", text: "오늘은 많이 피곤해요. 이제 잠깐 쉬고 싶어요.")
  ]
  static func title(for emotion: CharacterEmotion?) -> String {
    all.first { $0.emotion == emotion }?.title ?? "기본 표정"
  }
}
