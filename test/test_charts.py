import json
from common import post_innertube, HOST_MUSIC, CLIENT_WEB_REMIX

def test_charts():
    print("==========================================")
    print(" [TEST CHARTS] FEmusic_charts")
    print("==========================================")

    res = post_innertube(f"{HOST_MUSIC}/youtubei/v1/browse", {"browseId": "FEmusic_charts"}, CLIENT_WEB_REMIX)
    assert res and "contents" in res, "Failed to browse charts"

    tabs = res.get("contents", {}).get("singleColumnBrowseResultsRenderer", {}).get("tabs", [])
    assert len(tabs) > 0, "No tabs in charts"

    sec_list = tabs[0].get("tabRenderer", {}).get("content", {}).get("sectionListRenderer", {}).get("contents", [])
    assert len(sec_list) > 0, "No sections in charts"

    charts = []
    for sec in sec_list:
        carousel = sec.get("musicCarouselShelfRenderer", {})
        for it in carousel.get("contents", []):
            r = it.get("musicTwoRowItemRenderer")
            if r:
                t = "".join(x.get("text", "") for x in r.get("title", {}).get("runs", []))
                endpoint = r.get("navigationEndpoint", {}).get("browseEndpoint", {})
                b_id = endpoint.get("browseId")
                if b_id and t:
                    charts.append({"id": b_id, "name": t})

    print(f"Total charts discovered: {len(charts)}")
    assert len(charts) >= 4, f"Expected at least 4 charts, got {len(charts)}"
    for c in charts:
        print(f"  -> Chart: {c['name']} ({c['id']})")

    print(">>> CHARTS TEST PASSED <<<")
    return True

if __name__ == "__main__":
    test_charts()
