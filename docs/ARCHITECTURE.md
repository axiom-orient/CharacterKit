# CharacterKit

SEMI 한 캐릭터를 표현하는 Swift 6 패키지다. 호스트가 관측한 작업·감정·통신 상태를 받아 결정론적 pose와 scene으로 변환한다.

- 패키지: `CharacterKit`
- 공개 라이브러리: `ReactiveCharacterKit`
- 플랫폼 선언: iOS 16+, macOS 13+
- 외부 패키지 의존성: 없음

## 책임과 실행 경로

`CharacterEvent → reduce / act → CharacterState → CharacterPresentationSession → CharacterPose → CharacterSceneBuilder → CharacterScene → SVG / Canvas / PNG`

| 책임 | 소유자 |
|---|---|
| 앱의 작업 상태·외부 실행·영속성 | 호스트 |
| 캐릭터의 의미 상태 전이·입력 검증·시각 권한 순서 | `ReactiveCharacter.reduce` |
| 취소 요청과 종료 타이머 실행 | 호스트, `CharacterEffectPlan`을 적용 |
| 관측 결과를 다음 이벤트로 전달 | 호스트 |
| 일시적인 시각 전환·시선·음성 보간·계층별 시계 | `CharacterPresentationSession` |
| pose의 결정론적 계산 | Presentation |
| SEMI 도형과 이미지 배치 | `CharacterSceneBuilder` |
| 출력 인코딩·플랫폼별 그리기 | SVG / Apple renderer |

`CharacterState`가 의미 상태의 단일 정본이다. Presentation session은 의미 상태를 결정하지 않으며, scene과 renderer도 상태 기계를 갖지 않는다. SwiftUI의 timeline은 화면 갱신만 담당한다.

### 입력과 효과

```swift
import ReactiveCharacterKit

let taskID = try CharacterTaskID(validating: "summary-42")
var state = ReactiveCharacter.initialState
let receipt = ReactiveCharacter.act(
  state: state,
  event: .agentStarted(taskID: taskID)
)
state = receipt.stateAfter
```

호스트는 매 이벤트마다 다음 순서를 지킨다.

1. `receipt.stateAfter`를 저장한다.
2. 등록한 애니메이션 타이머 ID로 `receipt.effectPlan(scheduledAnimationIDs:)`를 구한다.
3. `animationIDsToCancel`의 타이머를 취소한다.
4. `effects`의 작업 취소 요청과 애니메이션 종료 예약을 실행한다.
5. 실제 결과를 같은 ID의 `CharacterEvent`로 보고한다.

`accepted`는 캐릭터 상태가 이벤트를 수락했다는 뜻이다. 외부 작업 성공을 뜻하지 않는다. `agentCancellationRequested`는 취소 요청이고, 완료 여부는 `agentCancelled`·`agentSucceeded`·`agentFailed`로 보고한다. 오래된 작업·애니메이션 결과와 중복 이벤트는 상태를 덮어쓰지 않는다. 진행률 회귀와 잘못된 수치는 거절한다.

진단을 기계적으로 처리할 때는 `receipt.diagnostic`의 schema `characterkit.action-diagnostic/1`, code, details를 사용한다. 설명 문장을 파싱하지 않는다.

### 화면 연결

```swift
import SwiftUI
import ReactiveCharacterKit

struct CharacterBadge: View {
  let state: CharacterState
  let statusText: String

  var body: some View {
    ReactiveCharacterView(
      state: state,
      accessibilityLabel: "세미",
      accessibilityValue: statusText
    )
    .frame(width: 200, height: 200)
    .characterReduceMotion(false)
  }
}
```

호스트가 지역화한 상태 문구를 `accessibilityValue`로 전달한다. 시스템 Reduce Motion 또는 호스트의 `characterReduceMotion(true)`가 활성화되면 반복적인 보조 움직임을 멈추고 상태를 읽을 수 있는 정지 pose를 표시한다.

`CharacterPresentationSession.update(state:at:reduceMotion:)`와 `pose(at:reduceMotion:)`를 직접 사용할 수도 있다. 입력 시간은 같은 단위의 단조 증가 초 값을 사용한다. 작업·표정·통신·애니메이션 시계를 분리해, 관계없는 이벤트가 진행 중인 동작을 처음부터 재생하지 않게 한다. 음성 레벨과 시선은 현재 보이는 위치에서 새 입력으로 전환한다.

일회성 애니메이션이 시각적으로 만료되면 유효한 의미 상태의 표현으로 돌아간다. 뒤늦은 종료 이벤트는 이 표현을 다시 시작하지 않는다. 이 규칙은 눈·표면뿐 아니라 귀·꼬리·수염에도 적용된다.

### 파일 출력

```swift
let pose = ReactiveCharacter.pose(state: state, elapsed: 0.8)
let scene = try CharacterSceneBuilder.scene(
  pose: pose, width: 320, height: 320
)
let svg = try CharacterSVGRenderer.render(
  scene, title: "SEMI", idPrefix: "summary-42"
)
```

SVG는 패키지 PNG를 data URI로 포함한다. 같은 문서에 SVG를 여러 개 삽입할 때는 서로 다른 `idPrefix`를 사용한다. title은 XML escape 처리하며 허용하지 않는 문자·잘못된 prefix·잘못된 viewport는 오류로 반환한다.

Apple 플랫폼의 `CharacterScenePNGRenderer.render(_:scale:)`는 `@MainActor`에서 같은 scene을 PNG로 출력한다. 이미지 누락, 인코딩 실패, 픽셀 예산 초과를 성공 이미지로 숨기지 않는다. Canvas는 이미지 해석 실패를 화면에 표시하며, `ReactiveCharacterView`는 해당 오류를 접근성 값으로도 전달한다.

## SEMI 표현 계약

- 번들 이미지는 머리, 좌우 귀, 좌우 발, 꼬리의 PNG 6개다.
- 눈·코·입·수염·문서·필기 선은 scene 도형으로 그린다.
- 입은 코 아래 짧은 인중과 두 입술 곡선으로 표현한다. 내부 채움·혀·벌어진 구강은 그리지 않는다. `mouth.openness`는 발화 강도의 수치이며 SEMI에서는 닫힌 입술의 움직임으로 사용한다.
- 수염은 볼마다 3개다. 일반 표정에서는 방향·길이·위상으로 반응하며, 반복 보조 움직임은 Reduce Motion을 따른다.
- 작은 viewport에서는 세부 표현을 줄여 읽기 쉬운 크기를 유지한다.
- 외형 선택 레지스트리 없이 `CharacterSceneBuilder.scene(pose:width:height:)`가 항상 SEMI를 만든다.

## 폴더

| 경로 | 내용 |
|---|---|
| `Sources/ReactiveCharacterKit` | Contract / Decision / Presentation / Appearance / Scene / ResourceIO / Rendering / UI |
| `Tests/ReactiveCharacterKitTests` | 상태·효과·전환·만료·scene·출력 계약 회귀 검증 |
| `Tools/Preview` | 공개 API를 호출하는 SVG 출력 실행 파일 |
| `Tools/HostDemo` | macOS에서 호스트 이벤트·취소·타이머·접근성을 확인하는 실행 앱 |
| `docs` | 현재 사용법과 설계 계약 |

Preview와 HostDemo는 루트 라이브러리를 참조하는 별도 실행 target이다. 구현을 복제하지 않는다. HostDemo의 작업 버튼은 호스트 이벤트를 주입하며, 실제 네트워크 에이전트 작업을 실행하지 않는다.

## 검증

저장소 루트에서 실행한다.

```sh
swift test --jobs 2
swift build -c release --jobs 2
swift run --package-path Tools/Preview --jobs 2 CharacterPreview --output .build/preview
```

macOS에서 실제 SwiftUI·Canvas·PNG 경로를 확인한다.

```sh
swift run --package-path Tools/HostDemo --jobs 2 CharacterHostDemo
```

Linux 검증은 상태·효과·presentation·scene·리소스·SVG를 실행한다. SwiftUI, native PNG, VoiceOver, 실제 기기의 프레임 성능은 Apple SDK와 실행 환경이 필요하다. Linux 통과를 Apple 실행 통과로 간주하지 않는다.
