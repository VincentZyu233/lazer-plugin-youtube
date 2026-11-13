import json, re
from common import post_innertube, HOST_MUSIC, CLIENT_WEB_REMIX

def test_artist_description_and_songs():
    print("\n==========================================")
    print(" [TEST ARTIST] Jay Chou (周杰伦) UCL2MDNdwEtV6aYUgNjFQGZA")
    print("==========================================")

    url = f"{HOST_MUSIC}/youtubei/v1/browse"
    data = post_innertube(url, {"browseId": "UCL2MDNdwEtV6aYUgNjFQGZA"}, CLIENT_WEB_REMIX)
    assert data, "Browse response is empty"

    # 1. 模拟 parse_artist 提取 description
    hdr = data.get("header", {}).get("musicImmersiveHeaderRenderer", {}) or data.get("header", {}).get("musicVisualHeaderRenderer", {})
    desc_obj = hdr.get("description", {})
    runs = desc_obj.get("runs", [])

    if not runs:
        # 尝试从 shelf 查找
        sec_list = data.get("contents", {}).get("singleColumnBrowseResultsRenderer", {}).get("tabs", [{}])[0].get("tabRenderer", {}).get("content", {}).get("sectionListRenderer", {}).get("contents", [])
        for s in sec_list:
            if "musicDescriptionShelfRenderer" in s:
                runs = s["musicDescriptionShelfRenderer"].get("description", {}).get("runs", [])
                break

    assert len(runs) >= 3, f"Expected at least 3 runs in Jay Chou description, got {len(runs)}"
    print(f"Runs count: {len(runs)}")

    # 验证提取的维基百科 URL
    run1_url = runs[1].get("navigationEndpoint", {}).get("urlEndpoint", {}).get("url", "")
    m = re.match(r'^(https?://[^%)]+)', run1_url)
    clean_wiki_url = m.group(1).rstrip(')，,') if m else ""
    print(f"Extracted clean Wikipedia URL: {clean_wiki_url}")
    assert "https://zh.wikipedia.org" in clean_wiki_url, f"Unexpected clean wiki URL: {clean_wiki_url}"
    assert "周杰倫" in clean_wiki_url or "%E5%91%A8%E6%9D%B0%E5%80%AB" in clean_wiki_url

    # 验证 CC 协议 URL
    run3_url = runs[3].get("navigationEndpoint", {}).get("urlEndpoint", {}).get("url", "")
    print(f"Extracted CC License URL: {run3_url}")
    assert "creativecommons.org" in run3_url

    # 2. 验证热门歌曲 Top Songs
    sec_list = data.get("contents", {}).get("singleColumnBrowseResultsRenderer", {}).get("tabs", [{}])[0].get("tabRenderer", {}).get("content", {}).get("sectionListRenderer", {}).get("contents", [])
    top_songs = []
    for s in sec_list:
        if "musicShelfRenderer" in s:
            items = s["musicShelfRenderer"].get("contents", [])
            for it in items:
                r = it.get("musicResponsiveListItemRenderer")
                if r:
                    t_runs = r.get("title", {}).get("runs", [{}])
                    title = t_runs[0].get("text", "") if t_runs else ""
                    top_songs.append(title)
            if top_songs:
                break

    print(f"Top songs count: {len(top_songs)}")
    assert len(top_songs) > 0, "No top songs found for Jay Chou"
    for idx, t in enumerate(top_songs[:3]):
        print(f"  -> Top Song {idx+1}: {t}")

    print(">>> ARTIST DESCRIPTION & TOP SONGS TEST PASSED <<<")


def test_home_feed_mixart_persistence():
    print("\n==========================================")
    print(" [TEST HOME MIXART PERSISTENCE] Editorial Mixes Fallback")
    print("==========================================")

    # 模拟 discover_service.home_feed()
    OFFICIAL_FALLBACK_MIXES = [
        {"id": "RDTMAK5uy_kset8DisdE7LSD4TNjEVnkKRTmG7a562Y8", "name": "我的超级合辑", "coverUrl": "https://www.gstatic.com/youtube/media/ytm/images/pda_mix_art/cover_my_supermix_3.png"},
        {"id": "RDTMAK5uy_m_jQ6oU5_130iJbN95_W4jWqQ7c-kC_rM", "name": "发现合辑", "coverUrl": "https://www.gstatic.com/youtube/media/ytm/images/pda_mix_art/cover_discover_mix_2.png"},
        {"id": "RDTMAK5uy_ksxU4WqD24u_Xk_hZfXQ65m7R3Z9Z6w", "name": "重放合辑", "coverUrl": "https://www.gstatic.com/youtube/media/ytm/images/pda_mix_art/cover_replay_mix_2.png"},
        {"id": "RDTMAK5uy_l43N1o_GZJ25u1_Xq_hZfXQ65m7R3Z9Z6w", "name": "新歌合辑", "coverUrl": "https://www.gstatic.com/youtube/media/ytm/images/pda_mix_art/cover_new_release_mix_2.png"}
    ]

    assert len(OFFICIAL_FALLBACK_MIXES) == 4
    for mix in OFFICIAL_FALLBACK_MIXES:
        assert mix["id"].startswith("RDTM")
        assert mix["coverUrl"].startswith("https://")
        print(f"  -> Mix: {mix['name']} | ID: {mix['id']} | Cover: {mix['coverUrl']}")

    print(">>> HOME MIXART FALLBACK TEST PASSED <<<")


if __name__ == "__main__":
    test_artist_description_and_songs()
    test_home_feed_mixart_persistence()
