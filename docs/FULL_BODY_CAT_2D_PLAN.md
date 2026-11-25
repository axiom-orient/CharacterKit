# 전신 고양이 SDK 사용과 검수

`CharacterFullBodyCatAppearance`에서 `.felt` 또는 `.crayon`, 기본 자세와 동작을 선택합니다. 두 스타일 모두 호스트가 넘긴 표정·시선·말하기 입력을 사용합니다.

```swift
ReactiveCharacterView(
  state: state,
  fullBodyCat: .init(pose: .standing, action: .wave, actionTrigger: waveCount, style: .felt)
)
```

동작을 다시 실행할 때 `actionTrigger`를 증가시키고, 취소할 때 `action`을 `nil`로 지정합니다. 걷기는 `walkDirection`, 털 세우기는 `puffDirection`으로 방향을 지정할 수 있습니다.

## 내부 구현

- 펠트는 22개 PNG와 압축된 자세 전환 좌표로 몸을 그립니다. 얼굴은 라이브로 합성합니다.
- 크레파스는 벡터 외곽선과 관절 위치를 보간합니다. 붓 자국은 각 파츠의 좌표를 따라갑니다.
- Canvas와 내보내기는 같은 장면 데이터를 사용합니다. [SDK 구조](ARCHITECTURE.md)

검증은 자세 전환, 접지, 앞발·꼬리 연결, 양방향 걷기·털 세우기, 발화와 PNG·SVG 출력을 포함합니다. [제작 자료](https://github.com/axiom-orient/CharacterKit/tree/main/Artwork/FullBodyCat) · [초기 연구와 설계 기록](https://github.com/axiom-orient/CharacterKit/blob/2.1.0/docs/FULL_BODY_CAT_2D_PLAN.md)
