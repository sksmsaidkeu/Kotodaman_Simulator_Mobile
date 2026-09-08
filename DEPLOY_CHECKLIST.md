# 배포 전 점검 체크리스트

APK를 빌드해 GitHub Releases에 올리기 전에 확인한다.

## 1. 불필요한 컨벤션 위반 코드

- [ ] `flutter analyze lib/`가 클린하다 (경고 0건)
- [ ] `print()` / `debugPrint()` 디버그 잔재가 없다 (사용자에게 보이는 로그가 아닌 개발용 출력)
- [ ] `TODO` / `FIXME` / `XXX` 주석이 남아 있지 않다
- [ ] 스파이크/실험용 페이지(`orb_spike_page.dart`, `orb_match_speed_page.dart`, `parallel_match_speed_page.dart` 등)가 실제 화면 네비게이션에서 진입 불가능하다

## 2. 민감 정보 노출

- [ ] `android/key.properties`와 `android/app/*.jks`가 git에 커밋되지 않았다 (`git ls-files | grep -E "key.properties|\.jks"` 결과 없음)
- [ ] 코드에 토큰/키 패턴(`ghp_`, `github_pat_`, `sk-`, `AKIA…`)이 하드코딩돼 있지 않다
- [ ] 로컬 절대경로(`C:\Users\…`, `/Users/…`)나 개인 이메일이 코드·주석에 노출되지 않는다
- [ ] `update_checker.dart`의 매니페스트 URL이 공개 raw GitHub 주소이고, 그 외 내부 전용 URL이 하드코딩돼 있지 않다
