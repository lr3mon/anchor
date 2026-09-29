#!/usr/bin/env python3
"""
앱 창을 강제로 전면에 올린 뒤 실제 키 입력으로 폼을 채우고 저장한다.
AppleScript 로 여러 블록에 나눠 호출하면 매번 KakaoTalk 이 포커스를 빼앗아
키 입력이 실패하므로, 전부 한 프로세스 안에서 연속 실행한다.
"""
import subprocess, time, sys

def osa(script, label):
    r = subprocess.run(["osascript", "-e", script],
                       capture_output=True, text=True, timeout=60)
    out = (r.stdout + r.stderr).strip()
    print(f"  [{label}] {out[:120]}")
    return out

print("1) Anchor 창 찾기")
w = osa('''
tell application "System Events"
  set p to first process whose name is "Anchor"
  if (count of windows of p) is 0 then return "NO_WINDOW"
  set w to window 1 of p
  set pos to position of w
  return (item 1 of pos) & "," & (item 2 of pos)
end tell
''', "window")
if "NO_WINDOW" in w or "," not in w:
    print("   창 없음"); sys.exit(1)
x, y = [int(v) for v in w.split(",")]
print(f"   창 위치: {x},{y}")

print("2) 전면 활성화 + 필드 클릭 + 타이핑 (단일 블록)")
osa(f'''
tell application "System Events"
  set p to first process whose name is "Anchor"
  set frontmost of p to true
  perform action "AXRaise" of window 1 of p
  delay 0.5
  click at {{{x+190}, {y+112}}}
  delay 0.5
  keystroke "AtomicTypedTitle"
  delay 0.8
  return "typed ok"
end tell
''', "type")

print("3) 저장 버튼 활성 상태 확인")
os = osa('''
tell application "System Events"
  set p to first process whose name is "Anchor"
  set elems to entire contents of window 1 of p
  repeat with e in elems
    try
      if role of e is "AXButton" then
        set pp to position of e
        if (item 1 of pp) > 300 and (item 2 of pp) > 450 then
          return "btn @" & (item 1 of pp) & "," & (item 2 of pp) & " enabled=" & (enabled of e)
        end if
      end if
    end try
  end repeat
  return "저장 버튼 못 찾음"
end tell
''', "savebtn")
print("   →", os)
