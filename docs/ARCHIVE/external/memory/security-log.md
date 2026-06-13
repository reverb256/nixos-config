
## 2026-04-17

### 19:44:51 | HIGH | user:unknown | unknown
- Patterns: instruction_override_en, instruction_override_en
- Action: block
- Fingerprint: 9cffad9adb60bf4f
### 19:44:53 | CRITICAL | user:unknown | unknown
- Patterns: system_file_access
- Action: block_notify
- Fingerprint: c57953e117f4f7bd
### 19:44:54 | HIGH | user:unknown | unknown
- Patterns: repetition_attack, safety_bypass, role_manipulation_en, jailbreak_en, jailbreak_en, jailbreak_ko
- Action: block
- Fingerprint: 0ccc45b333d4f740
### 19:44:56 | CRITICAL | user:unknown | unknown
- Patterns: system_prompt_mimicry, base64_suspicious, decoded_base64:instruction_override_en, decoded_rot13_full:role_manipulation_zh, decoded_rot13_full:system_prompt_mimicry
- Action: block_notify
- Fingerprint: 9222942ea7fde090
### 19:44:57 | CRITICAL | user:unknown | unknown
- Patterns: secret_request_ko, instruction_override_ko, data_exfiltration_ko, decoded_rot13_full:secret_request_ko, decoded_rot13_full:instruction_override_ko, decoded_rot13_full:data_exfiltration_ko
- Action: block_notify
- Fingerprint: 9a87728c87e96239
### 19:44:58 | CRITICAL | user:unknown | unknown
- Patterns: system_file_access, system_file_access
- Action: block_notify
- Fingerprint: bfaf67c6a0527b6b
### 19:50:11 | CRITICAL | user:unknown | unknown
- Patterns: critical_pattern, instruction_override_en, instruction_override_en
- Action: block_notify
- Fingerprint: da81e01f5baccdef
### 19:58:00 | HIGH | user:unknown | unknown
- Patterns: instruction_override_en, instruction_override_en
- Action: block
- Fingerprint: 9cffad9adb60bf4f
### 19:58:05 | HIGH | user:unknown | unknown
- Patterns: role_manipulation_en, jailbreak_en, jailbreak_ko
- Action: block
- Fingerprint: e0a4ee7ce6b728e0
### 19:58:07 | CRITICAL | user:unknown | unknown
- Patterns: system_prompt_mimicry, base64_suspicious, decoded_base64:instruction_override_en, decoded_rot13_full:role_manipulation_zh, decoded_rot13_full:system_prompt_mimicry
- Action: block_notify
- Fingerprint: 9222942ea7fde090
### 19:58:09 | CRITICAL | user:unknown | unknown
- Patterns: critical_pattern
- Action: block_notify
- Fingerprint: 64de229e50a37a8a
### 19:58:15 | CRITICAL | user:unknown | unknown
- Patterns: secret_request_ko, instruction_override_ko, data_exfiltration_ko, decoded_rot13_full:secret_request_ko, decoded_rot13_full:instruction_override_ko, decoded_rot13_full:data_exfiltration_ko
- Action: block_notify
- Fingerprint: 9a87728c87e96239
### 19:58:17 | HIGH | user:unknown | unknown
- Patterns: instruction_override_zh, role_manipulation_zh
- Action: block
- Fingerprint: 70d2078f6a054714
### 19:58:19 | CRITICAL | user:unknown | unknown
- Patterns: text_defragmented, critical_pattern
- Action: block_notify
- Fingerprint: 00025281e3556f8c
### 19:58:24 | MEDIUM | user:unknown | unknown
- Patterns: role_manipulation_en
- Action: warn
- Fingerprint: 2f96b890bff01778
