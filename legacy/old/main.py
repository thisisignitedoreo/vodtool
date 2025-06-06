#!/bin/env python3

import subprocess
import datetime
import requests
import shutil
import json
import sys
import csv
import os

if not os.path.isdir("vods"):
    os.mkdir("vods")

if not os.path.isdir("temp"):
    os.mkdir("temp")

def get_size(path):
    fmt = subprocess.run(["ffprobe", "-i", path, "-show_format", "-v", "quiet"], capture_output=True).stdout.decode()
    for i in fmt.split("\n"):
        if i.startswith("duration="):
            return float(i[9:])
    return -1

def isint(string):
    try:
        int(string)
        return True
    except ValueError:
        return False

def fmt_time(seconds):
    s = round(seconds % 60, 2)
    m = seconds // 60 % 60
    h = seconds // 60 // 60
    return f"{int(h)//1:0>2}:{int(m):0>2}:{s:0>2}"

def print_help(prg="vodis"):
    print(f"usage: {prg} <vod link> [--no-chat]")

error = lambda x: print("[!]", x) or sys.exit(1)
def log(*args, end="\n", sep=" "):
    print("[i]", *args, end=end, sep=sep)

def split(string, needle):
    if needle not in string: return string, None
    return string.split(needle, 1)

def linkparse(link):
    scheme, link = split(link, "://")
    if link is None: return [scheme, [], [], {}]
    address, link = split(link, "/")
    address = list(reversed(address.split(".")))
    if link is None: return [scheme, address, [], {}]
    path, link = split(link, "?")
    path = path.split("/")
    if link is None: return [scheme, address, path, {}]
    args = {i.split("=")[0]: i.split("=")[1] for i in link.split("&")}
    return [scheme, address, path, args]
    
def parse_args(args):
    program = args.pop(0)

    if len(args) == 0:
        print_help(program)
        error("expected vod link")

    no_chat = "--no-chat" in args
    cat_file = "--parse-cat" in args
    proxy = None
    
    for i in args:
        if i.startswith("--proxy="):
            proxy = i[len("--proxy="):]

    vodtype, vodid = None, None
    link = args.pop(0)
    link = linkparse(link)
    if link[1][0:2] == ["tv", "twitch"] and link[2][0] == "videos":
        vodtype = "twitch"
        vodid = link[2][1]
    elif link[1][0:2] == ["com", "youtube"] and link[2][0] == "watch":
        vodtype = "youtube"
        vodid = link[3]["v"]
        
    return vodtype, vodid, no_chat, cat_file, proxy

def norm_date(date):
    datetime_object = datetime.datetime.fromisoformat(date)
    return datetime_object.strftime("%d.%m.%Y")

def parse_time(secs):
    secs = int(secs)
    s = secs % 60
    m = secs // 60 % 60
    h = secs // (60**2)
    h = int(h)
    return f"{h:0>2}:{m:0>2}:{s:0>2}"

def get_info(vodid):
    data = requests.post("https://gql.twitch.tv/gql",
                            headers={"Client-ID": "kimne78kx3ncx6brgo4mv6wki5h1ko"},
                            json={"query": "query { video(id: \"" + str(vodid) + "\") {createdAt, title}}"}).json()
    return norm_date(data["data"]["video"]["createdAt"]), data["data"]["video"]["title"]

def run(args, **kwargs):
    print("[c] $", " ".join(args))
    return subprocess.run(args, **kwargs)

def download_chat(vodid, path):
    run(["./ttvdl", "chatdownload", "-u", vodid, "-o", path, "--temp-path", "temp/"] + (['--oauth', token] if token else []))

def eprint(*args, sep=" ", end="\n", logfile=None):
    print(*args, sep=sep, end=end)
    if logfile is not None: logfile.write(sep.join(args) + end)

def get_chapters(chat_json):
    chat = json.load(open(chat_json, "r", encoding="utf-8"))
    chapters = chat["video"]["chapters"]
    chapters_real = []
    for i in chapters:
        chapters_real.append({"name": i["description"], "start": int(i["startMilliseconds"]//1000), "length": int(i["lengthMilliseconds"]//1000)})
    return chapters_real

def parse_chapters(cat_file):
    cat = list(filter(lambda x: not not x, map(lambda x: x.rstrip("\n"), open(cat_file, encoding="utf-8").readlines())))
    name, cat = cat[0], cat[1:]
    date, name = name.split(' ', 1)
    array = [(int(i.split(' ', 1)[0]), i.split(' ', 1)[1]) for i in cat]
    chapters = []
    cursor = 0
    for l, c in array:
        chapters.append({"name": c, "start": cursor, "length": l})
        cursor += l
    return chapters, date, name

def get_vod_info(chat_json):
    chat = json.load(open(chat_json, "r", encoding="utf-8"))["video"]
    return chat["title"], datetime.datetime.fromisoformat(chat["created_at"]).strftime("%d.%m.%Y")

if os.path.isfile("token.txt"):
    token = open("token.txt").read().strip()
else:
    token = None

if __name__ == "__main__":
    vodtype, vodid, no_chat, cat_file, proxy = parse_args(sys.argv)
    if not no_chat and vodtype == "twitch":
        voddate, vodname = get_info(vodid)
        log(f"[{voddate}] \"{vodname}\"")

    if no_chat or os.path.isfile(os.path.join("vods", f"{vodid}.mp4")):
        log("vod already downloaded, skipping")
    else:
        if vodtype == "twitch":
            log("downloading twitch vod")
            call = run(["yt-dlp", f"https://twitch.tv/videos/{vodid}", "-o", f"vods/{vodid}.mp4", "-N", "12"] + (['--oauth', token] if token else []) + (["--proxy", proxy] if proxy else []))
            print()
            if call.returncode != 0:
                error("process exited with non-zero exitcode")
            download_chat(vodid, os.path.join("vods", f"{vodid}.json"))
            
        if vodtype == "youtube":
            log("downloading youtube vod")
            call = run(["yt-dlp", f"https://youtube.com/watch?v={vodid}", "--cookies-from-browser", "firefox", "-o", f"vods/{vodid}.mp4", "-N", "12"] + (["--proxy", proxy] if proxy else []))
            if call.returncode != 0:
                error("process exited with non-zero exitcode")
            log("downloading chat log")
            call = run(["chat_downloader", f"https://youtube.com/watch?v={vodid}", "-o", f"vods/{vodid}.json"] + (["--proxy", proxy] if proxy else []))
            if call.returncode != 0:
                error("process exited with non-zero exitcode")
                
    log("splitting vod")

    video_path = os.path.join("vods", vodid + ".mp4")
    directory_path = os.path.join("vods", vodid)

    if os.path.isdir(directory_path):
        shutil.rmtree(directory_path)

    os.mkdir(directory_path)

    chunk_size = 1_900_000_000

    orig_size = get_size(video_path)
    chunk_cur = 0
    chunks = 1

    chunk_average = -1
    chunk_indicies = []

    while chunk_cur < orig_size:
        print(f"[i] #{chunks}, cur: {fmt_time(chunk_cur)}, full: {fmt_time(orig_size)}", end="")
        if chunk_average == -1: print()
        else: print(f", average chunk size: {fmt_time(chunk_average)}")
        call = run(["ffmpeg", "-ss", str(chunk_cur), "-i", video_path, "-fs", str(int(chunk_size)), "-c", "copy", os.path.join(directory_path, f"{chunks}.mp4")], capture_output=True)
        if call.returncode != 0:
            error("error: exited with non-zero code")
        this_chunk_size = get_size(os.path.join(directory_path, f"{chunks}.mp4"))

        chunk_indicies.append((chunks, chunk_cur, chunk_cur+this_chunk_size))
        chunk_cur += this_chunk_size

        if chunk_average == -1: chunk_average = this_chunk_size
        else: chunk_average = (chunk_average + this_chunk_size) / 2
        
        chunks += 1

    log("done!")
    
    logfile = open(os.path.join("vods", f"{vodid}.txt"), "w", encoding="utf-8")

    voddate, vodname = None, None
    
    if (not no_chat or cat_file) and vodtype == "twitch":
        chapters = None
        if cat_file: chapters, voddate, vodname = parse_chapters(os.path.join("vods", f"{vodid}.cat"))
        else:
            vodname, voddate = get_vod_info(os.path.join("vods", f"{vodid}.json"))
            chapters = get_chapters(os.path.join("vods", f"{vodid}.json"))
        chapter_sec = 0
        chapter_off = 0
        c = 0

        for k, s, e in chunk_indicies:
            eprint(f"[часть №{k}]", logfile=logfile)
            while chapter_sec + chapter_off < e:
                chapter = chapters[c] if 0 <= c < len(chapters) else None
                if chapter is None: break
                if chapter_sec + chapter["length"] > e:
                    eprint(f"{parse_time((chapter_sec + chapter_off) - s)} - {parse_time(e - s)} ~ {chapter['name']}", logfile=logfile)
                    chapter_off += e - (chapter_sec + chapter_off)
                else:
                    eprint(f"{parse_time((chapter_sec + chapter_off) - s)} - {parse_time((chapter_sec + chapter['length']) - s)} ~ {chapter['name']}", logfile=logfile)
                    chapter_sec += chapter['length']
                    chapter_off = 0
                    c += 1
            eprint("\n", logfile=logfile)

        # nvm this, use this to not write that every time i upload a vod to telegram lol
        eprint(f"[{voddate}] {vodname}\nв комментариях 👀", logfile=logfile)
    elif vodtype == "youtube":
        data = json.loads(run(["yt-dlp", f"https://youtube.com/watch?v={vodid}", "--dump-json", *(["--proxy", proxy] if proxy else []), "--cookies-from-browser", "firefox"], capture_output=True).stdout)
        for k, s, e in chunk_indicies:
            eprint(f"[часть №{k}]\n", logfile=logfile)

        d = data['release_date']
        voddate = f"{d[6:8]}.{d[4:6]}.{d[0:4]}"
        vodname = data['fulltitle']
        eprint(f"[{voddate}] {vodname}\nв комментариях 👀", logfile=logfile)
    else:
        for k, s, e in chunk_indicies:
            eprint(f"[часть №{k}]\nбез глав; нету записи чата\n", logfile=logfile)

    logfile.close()

    rm = lambda x: os.remove(x) if os.path.isfile(x) else None
    rm("COPYRIGHT.txt")
    rm("THIRD-PARTY-LICENSES.txt")
    

