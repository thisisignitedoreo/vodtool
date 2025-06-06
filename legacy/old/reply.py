#!/bin/env python3

from pprint import pprint
import datetime
import pyrogram as pg
import tomllib, json
import tomli_w as tomlw
import time
import sys
import os

if not os.path.isfile('reply-config.toml'):
    tomlw.dump(open('reply-config.toml', 'wb'), {'conf': {'apiid': 0, 'apihash': '', 'chatge': '', 'groupge': ''}})
conf = tomllib.load(open('reply-config.toml', 'rb'))

api_id = conf['conf'].get('apiid', 0)
api_hash = conf['conf'].get('apihash', '')
chatge = conf['conf'].get('chatge', '')
groupge = conf['conf'].get('groupge', '')

app = pg.Client('my_account', api_id, api_hash)

if len(sys.argv) < 2:
    print('error: expected vodid as first argument')
    exit(1)

def listget(l, n, d=None):
    try: return l[n]
    except IndexError: return d

vodid = sys.argv[1]
wmsg = listget(sys.argv, 2)
wseg = listget(sys.argv, 3)

def parse_info(vodid):
    file = json.load(open(f'vods/{vodid}.map.json'))
    return file

def progress(seg, current, total):
    print(f"segment #{seg}: {round(current/total*100, 1):>5}%", end="\r")

chmap = parse_info(vodid)
info, segs = f"[{datetime.datetime.fromisoformat(chmap['date']).strftime('%d.%m.%y')}] {chmap['name']}\nв комментариях 👀", [ f"[часть №{k}]\n" '\n'.join([f"{j['name']}" for j in i]) for k, i in enumerate(chmap['chunks'], start=1) ]

def append_msg(chatid, msgid, addendum):
    old_content = app.get_messages(chatid, msgid).text
    app.edit_message_text(chatid, msgid, old_content + '\n' + addendum)

with app:
    if wmsg: msgorig = app.get_messages(chatge, int(wmsg))
    else: msgorig = app.send_message(chatge, info)
    #append_msg(*catalogmsg, f'{info.split("\n")[0].split(" ", 1)[0]} <a href="{msgorig.link}">{info.split("\n")[0].split(" ", 1)[1]}</a>')
    msg = app.get_discussion_message(chatge, msgorig.id)
    #msg = list(app.get_chat_history(groupge, limit=1))[0]
    print(f'sent channel msg {msgorig.link}')

    if not wseg: app.send_document(groupge, f'vods/{vodid}.json', caption="[запись чата]", reply_to_message_id=msg.id)
    print(f'sent chat captrure')

    print(f'sending segments')
    for k, seg in enumerate(segs, start=1):
        if len(seg.split('\n')) == 1 or (wseg is not None and k < int(wseg)): continue
        try: app.send_video(groupge, f"vods/{vodid}/{k}.mp4", caption=seg, reply_to_message_id=msg.id, progress=lambda x, y: progress(k, x, y), width=1920, height=1080)
        except pg.errors.FloodWait as e:
            time.sleep(e.x)
        print()

