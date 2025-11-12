# Karabiner 사용가이드

## 키 매핑

Caps Lock이 아닌 Right alt나 Right Command로 맵핑 가능.

- Karabiner 설정 중 
- Karabiner에서 Complex Modifications에서 아래의 rule을 새로 추가 후 적용

아래는 Caps Lock을 Right Alt로 맵핑 예시:

```json
{
    "description": "Right Alt를 Caps Lock으로 (반복 없음, 뗄 때는 무시)",
    "manipulators": [
        {
            "from": {
                "key_code": "right_alt",
                "modifiers": { "optional": ["any"] }
            },
            "to": [
                {
                    "key_code": "caps_lock",
                    "repeat": false
                }
            ],
            "to_after_key_up": [
                {
                    "set_variable": {
                        "name": "vk_none",
                        "value": 0
                    }
                }
            ],
            "type": "basic"
        }
    ]
}
```

## 충돌 해결

FOCD가 Karabiner같은 프로그램이나 내부 권한, 혹은 FOCD 개발 시, 충돌되었을 때의 해결법

1. '설정 > 일반 > 로그인 항목 > 백그라운드에서 허용' 에서 Karabiner와 관련된 사항의 토글 버튼을 오프,  FOCD 재부팅 후 다시 토글 온
<br>
    <img width="347" height="92" alt="image" src="https://github.com/user-attachments/assets/22a83f57-32db-4b07-89b2-08ca2e20b01c" /><br>

2. 1.이 안될 시, `tccutil`로 FOCD의 권한 초기화 후 다시 FOCD 실행

  ```bash
  $ tccutil reset All com.GST.focd
  ```


## Copyright

이 가이드는 [@hanbat1mj](https://github.com/hanbat1mj) 님의 도움으로 작성되었습니다.