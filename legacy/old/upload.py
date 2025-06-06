
import os
import sys
import time
import pyclip
import copying
import pyautogui

def diff(w1, w2):
    diff = []
    for i in w2:
        if i not in w1: diff.append(i)
    return diff

def lerp(a, b, t):
    return a + (b - a) * t

def upload(filepath, name, box):
    windows = pyautogui.getAllWindows()
    pyautogui.moveTo(box.left + 100, box.top + box.height - 10)
    pyautogui.click()
    time.sleep(0.5)
    newWindows = pyautogui.getAllWindows()
    diffWindows = diff(windows, newWindows)
    time.sleep(0.5)
    assert len(diffWindows) == 1
    fileWindow = diffWindows[0]
    pyautogui.moveTo(lerp(fileWindow.box.left, fileWindow.box.left + fileWindow.box.width, 0.5), fileWindow.box.top + fileWindow.box.height - 70)
    pyautogui.click()
    path = os.path.abspath(filepath)
    pyautogui.typewrite(path, interval=0.01)
    pyautogui.moveTo(fileWindow.box.left + fileWindow.box.width - 150, fileWindow.box.top + fileWindow.box.height - 40)
    pyautogui.click()

    cx, cy = lerp(box.left, box.left + box.width, 0.5), \
             lerp(box.top, box.top + box.height, 0.65)
    
    pyautogui.moveTo(cx, cy)
    time.sleep(2)
    pyautogui.click()

    pyclip.copy(name)
    pyautogui.hotkey("ctrl", "v")
    pyautogui.hotkey("enter")
    time.sleep(1)

def write(text, box):
    cx, cy = lerp(box.left, box.left + box.width, 0.5), \
             box.top + box.height - 20
    pyautogui.moveTo(cx, cy)
    pyautogui.click()

    pyclip.copy(text)
    pyautogui.hotkey("ctrl", "v")
    pyautogui.hotkey("enter")

if __name__ == "__main__":
    if len(sys.argv) == 4: use = int(sys.argv[3])
    else: use = None
    no_chat = "-no_chat" in sys.argv
    windows = pyautogui.getWindowsAt(*pyautogui.position())
    pyautogui.click()
    title, segments = copying.parse_info(sys.argv[1])
    if sys.argv[2] in "yYtTdD1":
        write(title, windows[0].box)
        time.sleep(0.5)
        pyautogui.moveTo(windows[0].box.left + 110, windows[0].box.top + windows[0].box.height - 90)
        pyautogui.click()
        time.sleep(5)
        
    if not no_chat and (use == 0 or not use): upload(f"vods/{sys.argv[1]}.json", "[запись чата]", windows[0].box)

    for k, i in enumerate(segments, start=1):
        if use and k < use: continue
        upload(f"vods/{sys.argv[1]}/{k}.mp4", i, windows[0].box)
