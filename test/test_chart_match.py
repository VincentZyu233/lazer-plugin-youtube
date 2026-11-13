# -*- coding: utf-8 -*-
"""
验证 Biliboard 榜单高频歌曲在 YouTube Music 搜索中的标题清洗与匹配得分
根据 Lazer `_chartMatchScore` (catalog.dart:808) 算法验证是否全部 >= 0.60
"""
import re
import urllib.request
import json

def clean_song_title(title, query):
    if not title:
        return title
    clean = title
    clean = re.sub(r'^[【\[][^】\]]*[】\]]\s*', '', clean)
    clean = re.sub(r'\s*[【\[][^】\]]*[】\]]$', '', clean)
    clean = re.sub(r'\s*[（\(](?:合作音乐人[：:].*?|feat\.?.*?|ft\.?.*?)[）\)]', '', clean, flags=re.IGNORECASE)
    clean = clean.strip()
    
    m = re.match(r'^(.*?)\s+[-/]\s+(.+)$', clean)
    if m:
        p1, p2 = m.group(1).strip(), m.group(2).strip()
        q_lower = query.lower() if query else ''
        p1_lower = p1.lower()
        p2_lower = p2.lower()
        if q_lower:
            if p1_lower == q_lower or p1_lower in q_lower or q_lower in p1_lower:
                clean = p1
            elif p2_lower == q_lower or p2_lower in q_lower or q_lower in p2_lower:
                clean = p2
        else:
            clean = p1
    return clean

def normalize(s):
    return re.sub(r'\s+', '', s or '').lower()

def chart_match_score(query, title, artist, candidate_title, candidate_artists):
    clean_title = normalize(title)
    clean_artist = normalize(artist)
    c_title = normalize(candidate_title)
    c_artist = normalize(' '.join(candidate_artists))

    score = 0.0
    if c_title == clean_title:
        score += 0.65
    elif clean_title in c_title or c_title in clean_title:
        score += 0.50

    if clean_artist and c_artist:
        if c_artist == clean_artist:
            score += 0.25
        elif clean_artist in c_artist or c_artist in clean_artist:
            score += 0.15

    return score

test_cases = [
    {
        "title": "シスターに懺悔を",
        "artist": "廃原メモリ",
    },
    {
        "title": "月が綺麗ねと言われたい！",
        "artist": "カササギ",
    },
    {
        "title": "えねみぃ",
        "artist": "ピノキオピー",
    },
    {
        "title": "ノンブレス・オブリージュ",
        "artist": "ピノキオピー",
    },
    {
        "title": "Displayholic",
        "artist": "AnythingBecomeMoe",
    },
]

def test_chart_match():
    print("==========================================")
    print(" [TEST CHART MATCH] Biliboard Simulation")
    print("==========================================")

    all_passed = True
    for tc in test_cases:
        query = f"{tc['title']} {tc['artist']}"
        req = urllib.request.Request(
            'https://music.youtube.com/youtubei/v1/search?prettyPrint=false',
            data=json.dumps({
                'context': {'client': {'clientName': 'WEB_REMIX', 'clientVersion': '1.20240101.01.00'}},
                'query': query
            }).encode('utf-8'),
            headers={'Content-Type': 'application/json', 'User-Agent': 'Mozilla/5.0'}
        )
        res = urllib.request.urlopen(req, timeout=10)
        data = json.loads(res.read().decode('utf-8'))

        best_score = 0.0
        best_candidate = None

        # traverse responsive list items
        def find_items(obj):
            if isinstance(obj, dict):
                if 'musicResponsiveListItemRenderer' in obj:
                    yield obj['musicResponsiveListItemRenderer']
                for v in obj.values():
                    yield from find_items(v)
            elif isinstance(obj, list):
                for item in obj:
                    yield from find_items(item)

        for it in list(find_items(data))[:8]:
            cols = it.get('flexColumns', [])
            if not cols:
                continue
            raw_title = cols[0].get('musicResponsiveListItemFlexColumnRenderer', {}).get('text', {}).get('runs', [{}])[0].get('text') or ''
            cleaned_title = clean_song_title(raw_title, query)
            
            c_artists = []
            if len(cols) > 1:
                for r in cols[1].get('musicResponsiveListItemFlexColumnRenderer', {}).get('text', {}).get('runs', []):
                    t = r.get('text', '').strip()
                    if t and t not in ('•', '·', '・', 'Song', 'Video'):
                        c_artists.append(t)

            score = chart_match_score(query, tc['title'], tc['artist'], cleaned_title, c_artists)
            if score > best_score:
                best_score = score
                best_candidate = (cleaned_title, c_artists, raw_title)

        print(f"Target: 《{tc['title']}》 by {tc['artist']}")
        if best_candidate:
            print(f"  Best Match: 《{best_candidate[0]}》 (raw: 《{best_candidate[2]}》) | Artists: {best_candidate[1]}")
            print(f"  Score: {best_score:.2f} (Threshold: 0.60) -> {'MATCHED' if best_score >= 0.60 else 'FAILED'}")
        else:
            print(f"  No items found! FAILED")

        if best_score < 0.60:
            all_passed = False

    print("==========================================")
    if all_passed:
        print(">>> ALL CHART MATCH TESTS PASSED <<<")
    else:
        raise Exception("Some chart match tests failed!")

if __name__ == "__main__":
    test_chart_match()
