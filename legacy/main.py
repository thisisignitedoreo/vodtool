
import sys
import colorama; colorama.just_fix_windows_console()
import os
import subprocess
import json
import datetime
import pyautogui
import pyclip
import time
import pprint

def log(*string):
    print(f" {colorama.Fore.BLUE}INFO{colorama.Style.RESET_ALL} ", *string)

def fatal(*string):
    print(f" {colorama.Back.RED}FATAL{colorama.Style.RESET_ALL}", *string)
    sys.exit(1)

def fatal_non_lethal(*string):
    print(f" {colorama.Back.RED}FATAL{colorama.Style.RESET_ALL}", *string)
    
def usage(*string):
    print(f" {colorama.Fore.GREEN}USAGE{colorama.Style.RESET_ALL}", *string)

def cmd(arglist, **kwargs):
    print(f" {colorama.Fore.YELLOW}CMD{colorama.Style.RESET_ALL}  ", *arglist)
    return subprocess.run(map(str, arglist), **kwargs)

def cmd_silent(arglist, **kwargs):
    return subprocess.run(map(str, arglist), **kwargs)

def isint(string):
    try:
        int(string)
        return True
    except ValueError:
        return False

def diff(w1, w2):
    diff = []
    for i in w2:
        if i not in w1: diff.append(i)
    return diff

def lerp(a, b, t):
    return a + (b - a) * t

def log_usage(program="vodtool"):
    usage(f"{program} <subcommand> [args]")
    usage(f"Subcommands:")
    usage(f" - `help`: print this message")
    usage(f"   args: none")
    usage(f" - `download`: download a stream, download a chat capture, split and generate chapter map")
    usage(f"   args: <link>")
    usage(f" - `categorize`: parse category file, split the vod and generate chapter map")
    usage(f"   args: <uid>")
    usage(f" - `print-chapter-map`: print a formatted chapter map")
    usage(f"   args: <uid>")
    usage(f" - `upload`: use pyautogui to upload the vod to Telegram")
    usage(f"   args: <uid> [--post] [--no-chat] [--from-chunk N]")
    usage(f" - `download-clips`: use pyautogui to upload the vod to Telegram")
    usage(f"   args: <clips.txt>")
    
def parse_args(args):
    program = args.pop(0)
    if len(args) == 0:
        log_usage(program)
        fatal("Expected a subcommand")

    subcommand = args.pop(0)

    if subcommand == "help":
        log_usage(program)
        sys.exit(0)
    elif subcommand == "download":
        if len(args) == 0:
            log_usage(program)
            fatal("Expected a link")
        link = args.pop(0)
        if not (link.startswith("https://twitch.tv/videos/") or link.startswith("https://www.twitch.tv/videos/")):
            fatal("Not a Twitch VOD link")
        return "download", [int(link.split("/")[4].split("?")[0])]
    elif subcommand == "categorize":
        if len(args) == 0:
            log_usage(program)
            fatal("Expected a UID")
        uid = args.pop(0)
        return "categorize", [uid]
    elif subcommand == "print-chapter-map":
        if len(args) == 0:
            log_usage(program)
            fatal("Expected an UID")
        
        return "print-chapter-map", [args.pop(0)]
    elif subcommand == "download-clips":
        if len(args) == 0:
            log_usage(program)
            fatal("Expected a clips file")
        
        return "download-clips", [args.pop(0)]
    elif subcommand == "upload":
        uid = None
        post = False
        chat = True
        from_chunk = 1

        n = 0
        while n < len(args):
            i = args[n]
            if i == "--post": post = True
            elif i == "--no-chat": chat = False
            elif i == "--from-chunk":
                n += 1
                from_chunk = args[n]
                if not isint(from_chunk): fatal(f"{from_chunk} is not a number")
                from_chunk = int(from_chunk)
                if from_chunk <= 0: fatal("--from-chunk should be 1 or more")
            else:
                if uid is None: uid = i
                else: fatal("Expected only one UID in arguments")
            n += 1
            
        if uid is None:
            log_usage(program)
            fatal("Expected an UID")
        
        return "upload", [uid, post, chat, from_chunk]
    else:
        log_usage(program)
        fatal("No such subcommand")

def makedir(path, silent=False):
    if not os.path.isdir(path):
        if not silent: log(f"No {path}/ directory, creating one")
        os.mkdir(path)

def download_vod(uid):
    if os.path.isfile(f"vods/{uid}.mp4"):
        log(f"VOD {uid} already downloaded, skipping")
    else:
        log(f"Downloading VOD {uid}")
        if cmd(["yt-dlp", f"https://twitch.tv/videos/{uid}", "-o", f"vods/{uid}.mp4", "-N", "12"]).returncode != 0:
            fatal("yt-dlp exited with non-zero exit code, bailing out")

def download_clip_video(uid):
    if os.path.isfile(f"clips/{uid}.mp4"):
        log(f"Clip {uid} already downloaded, skipping")
    else:
        log(f"Downloading clip {uid}")
        if cmd(["ttvdl", "clipdownload", "-u", uid, "-o", f"clips/{uid}.mp4"]).returncode != 0:
            fatal("ttvdl exited with non-zero exit code, bailing out")
        print()

def download_chat(uid, clip=False):
    if os.path.isfile(("clips" if clip else "vods") + f"/{uid}.json"):
        log(f"Chat Capture for " + ("clip" if clip else "VOD") + f" {uid} already downloaded, skipping")
    else:
        log(f"Downloading Chat Capture for " + ("clip" if clip else "VOD") + f" {uid}")
        if cmd(["ttvdl", "chatdownload", "-u", uid, "-o", ("clips" if clip else "vods") + f"/{uid}.json"]).returncode != 0:
            fatal("ttvdl exited with non-zero exit code, bailing out")

def pretty_bytes(b):
    if b < 1024: return f"{b}B"
    elif b < 1024**2: return f"{b/1024:.1f}KiB"
    elif b < 1024**3: return f"{b/(1024**2):.1f}MiB"
    elif b < 1024**4: return f"{b/(1024**3):.1f}GiB"
    return f"{b/(1024**4):.1f}TiB"

def pretty_time(s):
    m = int(s // 60)
    h = int(m // 60)
    s = int(s)
    return f"{h:0>2}:{m%60:0>2}:{s%60:0>2}"

def get_length(path):
    fmt = subprocess.run(["ffprobe", "-i", path, "-show_format", "-v", "quiet"], capture_output=True).stdout.decode()
    for i in fmt.split("\n"):
        if i.startswith("duration="):
            if i[9:12] == "N/A": return 1.0  # idk why but 0.0 breaks it
            return float(i[9:])

def split_vod(uid):
    makedir(f"vods/{uid}", True)
    if not os.path.isfile(f"vods/{uid}.mp4"):
        fatal(f"VOD {uid} is not downloaded, nothing to split")

    chunk_size = 2_000_000_000
    full_length = get_length(f"vods/{uid}.mp4")
    chunks = 0
    chunk_cursor = 0
    chunk_sizes = []
    
    log(f"Splitting VOD {uid}, chunk size ≈{pretty_bytes(chunk_size)}")

    while chunk_cursor < full_length:
        chunks += 1
        args = ["ffmpeg", "-ss", chunk_cursor, "-i", f"vods/{uid}.mp4", "-fs", chunk_size, "-c", "copy", f"vods/{uid}/{chunks}.mp4", "-y"]
        call = cmd_silent(args, capture_output=True)
        if call.returncode != 0:
            fatal_non_lethal("$ " + " ".join(map(str, args)))
            for i in call.stderr.split(b"\n"):
                fatal_non_lethal(i.decode())
            fatal("ffmpeg exited with non-zero exit code")
        chunk_length = get_length(f"vods/{uid}/{chunks}.mp4")
        chunk_sizes.append((chunk_cursor, chunk_length))
        chunk_cursor += chunk_length

        log(f"Chunk #{chunks}; Length: {pretty_time(chunk_length)}; File size: ≈{pretty_bytes(os.path.getsize(f'vods/{uid}/{chunks}.mp4'))}")

    log(f"Total chunks: {chunks}")
    return chunk_sizes

def get_chapters_from_cc(uid):
    chapters = []
    chat = json.load(open(f"vods/{uid}.json", encoding="utf-8"))
    for i in chat["video"]["chapters"]:
        chapters.append((i["description"], int(i["startMilliseconds"]/1000), int(i["lengthMilliseconds"]/1000)))
    return chapters

# вуа пуе_вфеу_тфьу_акщь_сс(гшв)Ж

def get_name_date_from_cc(uid):
    chat = json.load(open(f"vods/{uid}.json", encoding="utf-8"))
    return chat["video"]["title"], chat["video"]["created_at"]

def get_chapters_from_cat(uid):
    chapters = []
    chat = open(f"vods/{uid}.cat", encoding="utf-8").readlines()
    cur = 0
    for i in chat[1:]:
        length, name = i.rstrip().split(" ", 1)
        length = int(length)
        chapters.append((name, cur, length))
        cur += length
    return chapters

def get_name_date_from_cat(uid):
    date, name = open(f"vods/{uid}.cat", encoding="utf-8").readlines()[0].rstrip().split(" ", 1)
    return name, date
    
def generate_chapter_map(uid, chunk_lengths, vod_name, vod_date, chapters):
    log(f"Generating Chapter Map for VOD {uid}")
    output = {"name": vod_name, "date": vod_date, "chunks": []}

    chapter, chapter_start, chapter_offset = 0, 0, 0
    for chunk_start, chunk_length in chunk_lengths:
        chunk = []
        chunk_end = chunk_start + chunk_length

        while chapter_start + chapter_offset < chunk_end:
            if chapter >= len(chapters): break
            chapter_name, chapter_start, chapter_length = chapters[chapter]

            chunk.append({"name": chapter_name, "start": chapter_start + chapter_offset - chunk_start})
            if chapter_start + chapter_length > chunk_end:
                chapter_offset += chunk_start + chunk_length - chapter_start - chapter_offset
            else:
                chapter += 1
                chapter_offset = 0
        
        output["chunks"].append(chunk)

    json.dump(output, open(f"vods/{uid}.map.json", "w", encoding="utf-8"))

def write_post(text, box):
    cx, cy = lerp(box.left, box.left + box.width, 0.5), \
             box.top + box.height - 20
    pyautogui.moveTo(cx, cy)
    pyautogui.click()

    pyclip.copy(text)
    pyautogui.hotkey("ctrl", "v")
    pyautogui.hotkey("ctrl", "enter")

def upload_file(filepath, text, box):
    windows = pyautogui.getAllWindows()
    pyautogui.moveTo(box.left + 100, box.top + box.height - 10)
    pyautogui.click()
    time.sleep(0.5)
    newWindows = pyautogui.getAllWindows()
    diffWindows = diff(windows, newWindows)
    time.sleep(0.5)
    if len(diffWindows) != 1: fatal("Expected a file select window to appear")
    
    fileWindow = diffWindows[0]
    pyautogui.moveTo(lerp(fileWindow.box.left, fileWindow.box.left + fileWindow.box.width, 0.5), fileWindow.box.top + fileWindow.box.height - 70)
    pyautogui.click()
    path = os.path.abspath(filepath)
    pyclip.copy(path)
    pyautogui.hotkey("ctrl", "v")
    pyautogui.moveTo(fileWindow.box.left + fileWindow.box.width - 150, fileWindow.box.top + fileWindow.box.height - 40)
    pyautogui.click()

    cx, cy = lerp(box.left, box.left + box.width, 0.5), \
             lerp(box.top, box.top + box.height, 0.5)
    
    pyautogui.moveTo(cx, cy)
    time.sleep(2)
    pyautogui.click()

    pyclip.copy(text)
    pyautogui.hotkey("ctrl", "v")
    pyautogui.hotkey("ctrl", "enter")
    time.sleep(1)

def get_uid_from_clip_link(link):
    return link.split("/")[-1].split("?")[0]

def download_clip(link):
    uid = get_uid_from_clip_link(link)
    download_clip_video(uid)
    download_chat(uid, True)

if __name__ == "__main__":
    makedir("vods")
    operation, args = parse_args(sys.argv)
    if operation == "download":
        uid, = args

        download_vod(uid)
        download_chat(uid)

        generate_chapter_map(uid, split_vod(uid), *get_name_date_from_cc(uid), get_chapters_from_cc(uid))

        log("All done! Check vods/ folder.")

    elif operation == "categorize":
        uid, = args
        
        if not os.path.isfile(f"vods/{uid}.cat"):
            fatal("No such category file")
        if not os.path.isfile(f"vods/{uid}.mp4"):
            fatal("No such VOD file")
        
        generate_chapter_map(uid, split_vod(uid), *get_name_date_from_cat(uid), get_chapters_from_cat(uid))
    
        log("All done! Check vods/ folder.")
        
    elif operation == "print-chapter-map":
        uid, = args

        if not os.path.isfile(f"vods/{uid}.map.json"):
            fatal("No such chapter map")

        cm = json.load(open(f"vods/{uid}.map.json", encoding="utf-8"))
        
        for k, i in enumerate(cm["chunks"], 1):
            print(f"[часть №{k}]")
            for c in i: print(f"{pretty_time(c['start'])} - {c['name']}")
            print()

        print(f"[{datetime.datetime.fromisoformat(cm['date']).strftime('%d.%m.%Y')}] {cm['name']}\nв комментариях 👀")
        
    elif operation == "upload":
        uid, post, chat, from_chunk = args
        if not os.path.isfile(f"vods/{uid}.map.json"):
            fatal("No such chapter map")

        cm = json.load(open(f"vods/{uid}.map.json", encoding="utf-8"))

        log("Locating Telegram window")
        
        window = pyautogui.getWindowsAt(*pyautogui.position())[0].box
        pyautogui.click()
        
        if post:
            log("Sending main post and going to comments")
            write_post(f"[{datetime.datetime.fromisoformat(cm['date']).strftime('%d.%m.%Y')}] {cm['name']}\nв комментариях 👀", window)
            time.sleep(0.5)
            pyautogui.moveTo(window.left + 110, window.top + window.height - 90)
            pyautogui.click()
            time.sleep(5)

        if chat:
            log("Uploading chat capture")
            upload_file(f"vods/{uid}.json", "[запись чата]", window)

        for k, i in enumerate(cm["chunks"], 1):
            if k < from_chunk: continue
            log(f"Uploading chunk #{k}")
            output = f"[часть №{k}]\n"
            for c in i: output += f"{pretty_time(c['start'])} - {c['name']}\n"
            upload_file(f"vods/{uid}/{k}.mp4", output, window)

    elif operation == "download-clips":
        clips_file, = args
        if not os.path.isfile(clips_file): error(f"No such file as `{clips_file}`")
        clips = [i for i in open(clips_file).readlines() if i]
        makedir("clips")
        for clip_link in clips:
            download_clip(clip_link)
