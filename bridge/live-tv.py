#!/usr/bin/env python3
"""Read an IPTV M3U playlist into channels for the Media Player's Live TV page.

Hypnotix-style: a URL or a local .m3u, with #EXTINF attributes (name, group,
logo, id) and #EXTGRP groups. No content is bundled — the playlist source is
the person's own. Prints one JSON object: a list of channels, or {"error": ...}.
"""

from __future__ import annotations

import json
import re
import sys
import urllib.error
import urllib.request

TIMEOUT = 15
MAX_PLAYLIST = 8 * 1024 * 1024  # a playlist is text; cap a bad URL's response
UA = "shani-shell-live-tv/1.0 (+https://github.com/shani8dev/shani-shell)"
ATTR = re.compile(r'([\w-]+)="([^"]*)"')
FREE_TV_URL = "https://raw.githubusercontent.com/Free-TV/IPTV/master/playlist.m3u8"

# Free, legal, publicly available channels from the community list, so Live TV
# is useful on first open. Streams belong to their broadcasters; the shell hosts
# no content. The full community playlist is opt-in through the UI.
FREE_M3U = """
#EXTM3U
#EXTINF:-1 tvg-logo="https://i.imgur.com/QjJYohG.png" group-title="India",NDTV India
https://ndtvindiaelemarchana.akamaized.net/hls/live/2003679/ndtvindia/master.m3u8
#EXTINF:-1 tvg-logo="https://i.imgur.com/DKHUFVQ.png" group-title="India",ABP News
https://d2l4ar6y3mrs4k.cloudfront.net/live-streaming/abpnews-livetv/master.m3u8
#EXTINF:-1 tvg-logo="https://upload.wikimedia.org/wikipedia/commons/thumb/c/cd/ABP_Ananda_logo.svg/500px-ABP_Ananda_logo.svg.png" group-title="India",ABP Ananda
https://d2l4ar6y3mrs4k.cloudfront.net/live-streaming/ananda-livetv/master.m3u8
#EXTINF:-1 tvg-logo="https://i.imgur.com/9rBgkxG.png" group-title="India",TV9 Kannada
https://dyjmyiv3bp2ez.cloudfront.net/pub-iotv9kanmo6oiq/liveabr/playlist.m3u8
#EXTINF:-1 tvg-logo="https://i.imgur.com/oHAdC30.png" group-title="India",TV9 Telugu
https://dyjmyiv3bp2ez.cloudfront.net/pub-iotv9telcmjhcs/liveabr/playlist.m3u8
#EXTINF:-1 tvg-logo="https://i.imgur.com/k7urrIv.jpeg" group-title="India",TV9 Marathi
https://dyjmyiv3bp2ez.cloudfront.net/pub-iotv9marlygv8h/liveabr/playlist.m3u8
#EXTINF:-1 tvg-logo="https://upload.wikimedia.org/wikipedia/en/thumb/1/18/NDTV_Profit.svg/1280px-NDTV_Profit.svg.png" group-title="India",NDTV Profit
https://ndtvprofit.akamaized.net/hls/live/2107404/ndtvprofit/master_1.m3u8
#EXTINF:-1 tvg-logo="https://i.imgur.com/BR4BUAw.png" group-title="India",News18 India Ⓨ
https://nw18live.cdn.jio.com/bpk-tv/News18_India_NW18_MOB/output01/index.m3u8
#EXTINF:-1 tvg-logo="https://i.imgur.com/K3M8MoK.png" group-title="India",CNN-News18
https://nw18live.cdn.jio.com/bpk-tv/CNN_News18_NW18_MOB/output01/index.m3u8
#EXTINF:-1 tvg-logo="https://i.imgur.com/CQUGLoK.png" group-title="India",News18 Kannada
https://nw18live.cdn.jio.com/bpk-tv/News18_Kannada_NW18_MOB/output01/index.m3u8
#EXTINF:-1 tvg-logo="https://i.imgur.com/A1xzjOI.png" group-title="News",DW
https://dwamdstream102.akamaized.net/hls/live/2015525/dwstream102/index.m3u8
#EXTINF:-1 tvg-logo="https://i.imgur.com/BB93NQP.png" group-title="News",Al Jazeera
https://live-hls-apps-aje-fa.getaj.net/AJE/index.m3u8
#EXTINF:-1 tvg-logo="https://i.imgur.com/fMsJYzl.png" group-title="News",CGTN
https://news.cgtn.com/resource/live/english/cgtn-news.m3u8
#EXTINF:-1 tvg-logo="https://raw.githubusercontent.com/tv-logo/tv-logos/main/countries/united-kingdom/nbc-news-now-uk.png" group-title="News",NBC News NOW
https://d1si3n1st4nkgb.cloudfront.net/10502/88896001/hls/master.m3u8?ads.xumo_channelId=88896001
#EXTINF:-1 tvg-logo="https://i.imgur.com/6eQ2nCJ.png" group-title="News",Reuters
https://amg00453-reuters-amg00453c1-rakuten-uk-2110.playouts.now.amagi.tv/playlist/amg00453-reuters-reuters-rakutenuk/playlist.m3u8
#EXTINF:-1 tvg-logo="https://raw.githubusercontent.com/tv-logo/tv-logos/main/countries/united-states/cbs-news-us.png" group-title="News",CBS News
https://dai.google.com/linear/hls/event/Sid4xiTQTkCT1SLu6rjUSQ/master.m3u8
#EXTINF:-1 tvg-logo="https://raw.githubusercontent.com/tv-logo/tv-logos/main/countries/united-states/abc-news-live-hz-us.png" group-title="News",ABC News Live
https://abcnews-streams.akamaized.net/hls/live/2023560/abcnewshudson1/master.m3u8
#EXTINF:-1 tvg-logo="https://i.imgur.com/1JnyzHv.png" group-title="News",LiveNOW from FOX
https://fox-foxnewsnow-vizio.amagi.tv/playlist.m3u8
#EXTINF:-1 tvg-logo="https://i.imgur.com/koFYddE.png" group-title="News",India Today
https://indiatodaylive.akamaized.net/hls/live/2014320/indiatoday/indiatodaylive/playlist.m3u8
#EXTINF:-1 tvg-logo="https://i.imgur.com/aiiinzg.png" group-title="News",Metro Globe Network
https://edge.medcom.id/live-edge/smil:mgnch.smil/playlist.m3u8
#EXTINF:-1 tvg-logo="https://i.imgur.com/UfN6aAi.png" group-title="News",Scripps News
https://content.uplynk.com/channel/4bb4901b934c4e029fd4c1abfc766c37.m3u8
#EXTINF:-1 tvg-logo="https://i.imgur.com/37K0AZX.png" group-title="News",USA Today
https://cdn-ue1-prod.tsv2.amagi.tv/linear/amg00731-gannettcoinc-usatodaynews-plex/playlist.m3u8
#EXTINF:-1 tvg-logo="https://i.imgur.com/xk1QOhW.png" group-title="News",Global News
https://live.corusdigitaldev.com/groupd/live/49a91e7f-1023-430f-8d66-561055f3d0f7/live.isml/.m3u8
#EXTINF:-1 tvg-logo="https://upload.wikimedia.org/wikipedia/commons/thumb/a/a0/Russia-today-logo.svg/500px-Russia-today-logo.svg.png" group-title="News",Russia Today Ⓖ
https://rt-glb.rttv.com/live/rtnews/playlist.m3u8
#EXTINF:-1 tvg-logo="https://i.imgur.com/KxHWpQB.png" group-title="News",TalkTV
https://488f4ce4.wurl.com/master/f36d25e7e52f1ba8d7e56eb859c636563214f541/TEctZ2JfVGFsa19ITFM/playlist.m3u8
#EXTINF:-1 tvg-logo="https://i.imgur.com/H9q3Q9d.png" group-title="News",SABC News
https://sabconetanw.cdn.mangomolo.com/news/smil:news.stream.smil/chunklist_b250000_t64MjQwcA==.m3u8
#EXTINF:-1 tvg-logo="https://i.imgur.com/vrcbnBv.png" group-title="UK",S4C Ⓖ
https://live-uk.s4c-cdn.co.uk/out/v1/a0134f1fd5a2461b9422b574566d4442/live_uk.m3u8
#EXTINF:-1 tvg-logo="https://i.imgur.com/fk5rEje.png" group-title="UK",TJC
https://cdn-shop-lc-01.akamaized.net/Content/HLS_HLS/Live/channel(TJCOTT)/index.m3u8
#EXTINF:-1 tvg-logo="https://upload.wikimedia.org/wikipedia/en/thumb/9/92/Great%21_Movies_logo_2021.svg/500px-Great%21_Movies_logo_2021.svg.png" group-title="UK",Great! Movies Ⓢ
https://amg01753-narrativeuk-amg01753c3-lg-gb-1833.playouts.now.amagi.tv/playlist/amg01753-narrativeuk-greatmovies-lggb/playlist.m3u8
#EXTINF:-1 tvg-logo="https://i.imgur.com/IR2sTag.png" group-title="UK",GemsTV Ⓢ
https://lo3.gemporia.com/abrgemporiaukgfx/smil:livestream.smil/playlist.m3u8
#EXTINF:-1 tvg-logo="https://www.freeview.co.uk/sites/default/files/styles/255_wide/public/2023-09/GREAT-Christmas-logo.png" group-title="UK",Great! Romance Ⓢ
https://amg01753-narrativeuk-amg01753c2-lg-gb-1832.playouts.now.amagi.tv/playlist/amg01753-narrativeuk-greatchristmas-lggb/playlist.m3u8
#EXTINF:-1 tvg-logo="https://i.imgur.com/9vzEz1b.png" group-title="UK",TBN UK Ⓢ
https://live-tbn-ssai.simplestreamcdn.com/v1/master/774d979dd66704abea7c5b62cb34c6815fda0d35/tbn-live/manifest.m3u8
#EXTINF:-1 tvg-logo="https://raw.githubusercontent.com/dp247/mediaportal-uk-logos/master/TV/True-Crime-UK.png" group-title="UK",True Crime Ⓢ
https://b6cca454.wurl.com/master/f36d25e7e52f1ba8d7e56eb859c636563214f541/U2Ftc3VuZy1nYl9UcnVlQ3JpbWVVS2Zyb21DQlNSZWFsaXR5X0hMUw/playlist.m3u8
#EXTINF:-1 tvg-logo="https://i.imgur.com/O7SdkBh.png" group-title="UK",Jewellery Maker
https://lo3.gemporia.com/abrjewellerymaker/smil:livestreamFullHD.smil/playlist.m3u8
#EXTINF:-1 tvg-logo="https://i.imgur.com/VWHp5Tl.png" group-title="UK",Hobby Maker
https://lo3.gemporia.com/abrhobbymakerukgfx/smil:livestreamFullHD.smil/playlist.m3u8
#EXTINF:-1 tvg-logo="https://upload.wikimedia.org/wikipedia/en/thumb/3/36/Pop_UK_TV_Logo_%282015%29.svg/500px-Pop_UK_TV_Logo_%282015%29.svg.png" group-title="UK",Pop Ⓢ
https://amg01753-narrativeentert-popkids-lggb-xyy5k.amagi.tv/ts-eu-w1-n2/playlist/amg01753-narrativeentert-popkids-lggb/playlist.m3u8
#EXTINF:-1 tvg-logo="https://upload.wikimedia.org/wikipedia/commons/thumb/a/a2/BBC_News_2022_%28Alt%29.svg/500px-BBC_News_2022_%28Alt%29.svg.png" group-title="UK",BBC News
https://vs-hls-push-ww-live.akamaized.net/x=4/i=urn:bbc:pips:service:bbc_news_channel_hd/t=3840/v=pv14/b=5070016/main.m3u8
#EXTINF:-1 tvg-logo="https://upload.wikimedia.org/wikipedia/en/thumb/3/35/GB_News_Logo.svg/500px-GB_News_Logo.svg.png" group-title="UK",GB News
https://live-gbnews.simplestreamcdn.com/live5/gbnews/bitrate1.isml/manifest.m3u8
#EXTINF:-1 tvg-logo="https://i.imgur.com/cbGvXyF.jpg" group-title="USA",Biz TV
https://2-fss-1.streamhoster.com/pl_154/205722-2251224-1/playlist.m3u8
#EXTINF:-1 tvg-logo="https://i.imgur.com/VnCcH73.png" group-title="USA",Bloomberg
https://bloomberg.com/media-manifest/streams/us.m3u8
#EXTINF:-1 tvg-logo="https://i.imgur.com/7sJLzKi.png" group-title="USA",ABC News
https://abcnews-streams.akamaized.net/hls/live/2023560/abcnewshudson1/master.m3u8
#EXTINF:-1 tvg-logo="https://i.imgur.com/nki2HDQ.png" group-title="USA",CBS News
https://cbsnews.akamaized.net/hls/live/2020607/cbsnlineup_8/master.m3u8
#EXTINF:-1 tvg-logo="https://i.imgur.com/v48mMRT.png" group-title="USA",NBC News
https://d1bl6tskrpq9ze.cloudfront.net/hls/master.m3u8?ads.xumo_channelId=99984003
#EXTINF:-1 tvg-logo="https://i.imgur.com/rmyfoOI.png" group-title="USA",NASA TV Media
https://ntv2.akamaized.net/hls/live/2013923/NASA-NTV2-HLS/master.m3u8
#EXTINF:-1 tvg-logo="https://i.imgur.com/N3xiz4m.png" group-title="USA",BBC Food
https://service-stitcher.clusters.pluto.tv/v1/stitch/embed/hls/channel/5fb5844bf5514d0007945bda/master.m3u8?deviceId=channel&deviceModel=web&deviceVersion=1.0&appVersion=1.0&deviceType=rokuChannel&deviceMake=rokuChannel&deviceDNT=1&advertisingId=channel&embedPartner=rokuChannel&appName=rokuchannel&is_lat=1&bmodel=bm1&content=channel&platform=web&tags=ROKU_CONTENT_TAGS&coppa=false&content_type=livefeed&rdid=channel&genre=ROKU_ADS_CONTENT_GENRE&content_rating=ROKU_ADS_CONTENT_RATING&studio_id=viacom&channel_id=channel
#EXTINF:-1 tvg-logo="https://i.imgur.com/Ii8DX1x.png" group-title="USA",BBC Home
https://service-stitcher.clusters.pluto.tv/v1/stitch/embed/hls/channel/5fb5836fe745b600070fc743/master.m3u8?deviceId=channel&deviceModel=web&deviceVersion=1.0&appVersion=1.0&deviceType=rokuChannel&deviceMake=rokuChannel&deviceDNT=1&advertisingId=channel&embedPartner=rokuChannel&appName=rokuchannel&is_lat=1&bmodel=bm1&content=channel&platform=web&tags=ROKU_CONTENT_TAGS&coppa=false&content_type=livefeed&rdid=channel&genre=ROKU_ADS_CONTENT_GENRE&content_rating=ROKU_ADS_CONTENT_RATING&studio_id=viacom&channel_id=channel
#EXTINF:-1 tvg-logo="https://i.imgur.com/EldlmTp.png" group-title="USA",Drybar Comedy
https://drybar-drybarcomedy-1-us.samsung.wurl.tv/playlist.m3u8
#EXTINF:-1 tvg-logo="https://stryktv.com/wp-content/uploads/2021/08/StrykTV-MTS.png" group-title="USA",Stryk TV
https://FFFFFFF110156200.tvustream.com/ryfy.m3u8
#EXTINF:-1 tvg-logo="https://graph.facebook.com/livenowfox/picture?width=200&height=200" group-title="USA",FOX Live Now
https://fox-foxnewsnow-vizio.amagi.tv/playlist.m3u8
#EXTINF:-1 tvg-logo="https://graph.facebook.com/cheddar/picture?width=200&height=200" group-title="USA",Cheddar
https://hls.livecdn.io/cheddar.com/cheddar/playlist.m3u8
#EXTINF:-1 tvg-logo="https://upload.wikimedia.org/wikipedia/commons/thumb/c/ca/Das_Erste_2014.svg/500px-Das_Erste_2014.svg.png" group-title="Germany",Das Erste Ⓖ
https://daserste-live.ard-mcdn.de/daserste/live/hls/de/master.m3u8
#EXTINF:-1 tvg-logo="https://upload.wikimedia.org/wikipedia/commons/thumb/4/4b/ARD_alpha.svg/500px-ARD_alpha.svg.png" group-title="Germany",ARD Alpha Ⓖ
https://mcdn.br.de/br/fs/ard_alpha/hls/de/master.m3u8
#EXTINF:-1 tvg-logo="https://i.imgur.com/E65GQN9.png" group-title="Germany",DELUXE MUSIC
https://sdn-global-live-streaming-packager-cache.3qsdn.com/13456/13456_264_live.m3u8
#EXTINF:-1 tvg-logo="https://upload.wikimedia.org/wikipedia/commons/thumb/c/c2/Deluxe_Dance_by_Kontor_Logo_2023.svg/500px-Deluxe_Dance_by_Kontor_Logo_2023.svg.png" group-title="Germany",DELUXE MUSIC DANCE BY KONTOR
https://sdn-global-live-streaming-packager-cache.3qsdn.com/64733/64733_264_live.m3u8
#EXTINF:-1 tvg-logo="https://upload.wikimedia.org/wikipedia/commons/thumb/0/07/Deluxe_Rap_Logo_2023.svg/500px-Deluxe_Rap_Logo_2023.svg.png" group-title="Germany",DELUXE MUSIC RAP
https://sdn-global-live-streaming-packager-cache.3qsdn.com/65183/65183_264_live.m3u8
#EXTINF:-1 tvg-logo="https://upload.wikimedia.org/wikipedia/commons/thumb/f/f5/Kika_2012.svg/500px-Kika_2012.svg.png" group-title="Germany",KiKa Ⓖ
https://kikageohls.akamaized.net/hls/live/2022693/livetvkika_de/master.m3u8
#EXTINF:-1 tvg-logo="https://upload.wikimedia.org/wikipedia/commons/thumb/2/24/Tagesschau24-2012.svg/500px-Tagesschau24-2012.svg.png" group-title="Germany",Tagesschau24
https://tagesschau.akamaized.net/hls/live/2020115/tagesschau/tagesschau_1/master.m3u8
#EXTINF:-1 tvg-logo="https://upload.wikimedia.org/wikipedia/commons/thumb/9/9b/Logo_BR_Fernsehen_2021.svg/500px-Logo_BR_Fernsehen_2021.svg.png" group-title="Germany",BR Nord Ⓖ
https://mcdn.br.de/br/fs/bfs_nord/hls/de/master.m3u8
#EXTINF:-1 tvg-logo="https://upload.wikimedia.org/wikipedia/commons/thumb/9/9b/Logo_BR_Fernsehen_2021.svg/500px-Logo_BR_Fernsehen_2021.svg.png" group-title="Germany",BR Süd Ⓖ
https://mcdn.br.de/br/fs/bfs_sued/hls/de/master.m3u8
#EXTINF:-1 tvg-logo="https://upload.wikimedia.org/wikipedia/commons/thumb/e/ea/HR-Fernsehen_Logo_2023.svg/500px-HR-Fernsehen_Logo_2023.svg.png" group-title="Germany",HR Ⓖ
https://hrhlsde.akamaized.net/hls/live/2024526/hrhlsde/master.m3u8
#EXTINF:-1 tvg-logo="https://i.imgur.com/fMsJYzl.png" group-title="France",CGTN Français
https://news.cgtn.com/resource/live/french/cgtn-f.m3u8
#EXTINF:-1 group-title="France",Handicap TV
https://srv.webtvmanager.fr:3697/stream/play.m3u8
#EXTINF:-1 group-title="France",Air Connect TV
https://tv.airconnectradio.com/live.m3u8
#EXTINF:-1 tvg-logo="https://i.imgur.com/NcysrWH.png" group-title="France",TV5 Monde Info
https://ott.tv5monde.com/Content/HLS/Live/channel(info)/index.m3u8
#EXTINF:-1 tvg-logo="https://upload.wikimedia.org/wikipedia/commons/thumb/b/b6/Logo_BFM_TV_%282019%29.png/60px-Logo_BFM_TV_%282019%29.png" group-title="France",BFM TV
https://ncdn-live-bfm.pfd.sfr.net/shls/LIVE$BFM_TV/index.m3u8?end=END&start=LIVE
#EXTINF:-1 tvg-logo="https://i.imgur.com/NbesiPn.png" group-title="Spain",La 1
https://rtvelivestream.rtve.es/rtvesec/la1/la1_main_dvr.m3u8
#EXTINF:-1 tvg-logo="https://i.imgur.com/DmuTwDw.png" group-title="Spain",La 2
https://rtvelivestream.rtve.es/rtvesec/la2/la2_main_dvr.m3u8
#EXTINF:-1 tvg-logo="https://i.imgur.com/ZKR2jKr.png" group-title="Spain",24h
https://rtvelivestream.rtve.es/rtvesec/24h/24h_main_dvr.m3u8
#EXTINF:-1 tvg-logo="https://i.imgur.com/HliegRJ.png" group-title="Spain",tdp
https://rtvelivestream.rtve.es/rtvesec/tdp/tdp_main.m3u8
#EXTINF:-1 tvg-logo="https://i.imgur.com/38xIfQ3.png" group-title="Spain",clan
https://rtvelivestream.rtve.es/rtvesec/clan/clan_main_dvr.m3u8
#EXTINF:-1 tvg-logo="https://i.imgur.com/ow1HArj.png" group-title="Spain",TVE Internacional Europe-Asia
https://rtvelivestream-rtveplayplus.rtve.es/rtvesec/int/tvei_eu_main_dvr_1080.m3u8
#EXTINF:-1 tvg-logo="https://upload.wikimedia.org/wikipedia/commons/thumb/9/9f/Paramount_Network.svg/500px-Paramount_Network.svg.png" group-title="Spain",Paramount Network
https://jmp2.uk/plu-68d566603d3a9580eb461251.m3u8
#EXTINF:-1 tvg-logo="https://graph.facebook.com/radionacionalrne/picture?width=200&height=200" group-title="Spain",RNE para todos
https://rtvelivestream.rtve.es/rtvesec/rne/rne_para_todos_main.m3u8
#EXTINF:-1 tvg-logo="https://raw.githubusercontent.com/tv-logo/tv-logos/refs/heads/main/countries/international/euro-news-int.png" group-title="Spain",euronews
https://euronews-live-spa-es.fast.rakuten.tv/v1/master/0547f18649bd788bec7b67b746e47670f558b6b2/production-LiveChannel-6571/bitok/eyJzdGlkIjoiMDA0YjY0NTMtYjY2MC00ZTZkLTlkNzEtMTk3YTM3ZDZhZWIxIiwibWt0IjoiZXMiLCJjaCI6NjU3MSwicHRmIjoxfQ==/26034/euronews-es.m3u8
#EXTINF:-1 tvg-logo="https://graph.facebook.com/elpais/picture?width=200&height=200" group-title="Spain",El País
https://d2epgk1fomaa1g.cloudfront.net/v1/master/3722c60a815c199d9c0ef36c5b73da68a62b09d1/cc-9n8y4tw0bk3an/live/fast-channel-el-pais/fast-channel-el-pais.m3u8
#EXTINF:-1 tvg-logo="https://upload.wikimedia.org/wikipedia/commons/thumb/6/64/Russia-1.svg/960px-Russia-1.svg.png" group-title="Russia",Россия 1
https://live.smotrim.ru/vgtrk/0/russia1-hd/index.m3u8
#EXTINF:-1 tvg-logo="https://i.imgur.com/S12gaLc.png" group-title="Russia",Россия-Культура Ⓢ
https://live.smotrim.ru/vgtrk/0/kultura-hd/index.m3u8
#EXTINF:-1 tvg-logo="https://i.imgur.com/c0L0ncA.png" group-title="Russia",Звезда
https://tvchannelstream1.tvzvezda.ru/cdn/tvzvezda/playlist.m3u8
#EXTINF:-1 tvg-logo="https://i.imgur.com/fMsJYzl.png" group-title="Russia",CGTN Pусский
https://news.cgtn.com/resource/live/russian/cgtn-r.m3u8
#EXTINF:-1 group-title="Russia",Че
https://cdn4.skygo.mn/live/disk1/Che/HLSv3-FTA/Che.m3u8
#EXTINF:-1 tvg-logo="https://i.imgur.com/mve0sSS.png" group-title="Russia",Архыз 24
https://live.mediacdn.ru/sr1/arhis24/playlist_hdhigh.m3u8
#EXTINF:-1 tvg-logo="https://i.imgur.com/9WcnjQN.png" group-title="Russia",Астрахан 24
https://streaming.astrakhan.ru/astrakhan24/playlist.m3u8
#EXTINF:-1 tvg-logo="https://i.imgur.com/gXbUMVy.png" group-title="Russia",Москва 24
https://stream.smotrim.ru/hls/moscow_24/playlist.m3u8?entity=channel&id=76&sign=e8e1bc15ce94ee7718ef8948500e5d21
#EXTINF:-1 tvg-logo="https://i.imgur.com/eEV4r6J.jpg" group-title="United Arab Emirates",Al Arabiya Business
https://live.alarabiya.net/alarabiapublish/aswaaq.smil/playlist.m3u8
#EXTINF:-1 tvg-logo="https://i.imgur.com/CiA3plN.png" group-title="United Arab Emirates",MBC 1
https://shd-gcp-live.edgenextcdn.net/live/bitmovin-mbc-1/15cf99af5de54063fdabfefe66adc075/index.m3u8
#EXTINF:-1 tvg-logo="https://i.imgur.com/PVt8OPN.png" group-title="United Arab Emirates",MBC 3
https://shd-gcp-live.edgenextcdn.net/live/bitmovin-mbc-3-usa/5d58265a862a476dc7f97694addb5ded/index.m3u8
#EXTINF:-1 tvg-logo="https://i.imgur.com/BcXASJp.png" group-title="United Arab Emirates",MBC 4
https://shd-gcp-live.edgenextcdn.net/live/bitmovin-mbc-4/24f134f1cd63db9346439e96b86ca6ed/index.m3u8
#EXTINF:-1 tvg-logo="https://i.imgur.com/fRWaDyF.png" group-title="United Arab Emirates",MBC 5
https://shd-gcp-live.edgenextcdn.net/live/bitmovin-mbc-5/ee6b000cee0629411b666ab26cb13e9b/index.m3u8
#EXTINF:-1 tvg-logo="https://i.imgur.com/TTAGFHG.png" group-title="United Arab Emirates",MBC Bollywood
https://shd-gcp-live.edgenextcdn.net/live/bitmovin-mbc-bollywood/546eb40d7dcf9a209255dd2496903764/index.m3u8
#EXTINF:-1 tvg-logo="https://i.imgur.com/CAx7yRm.png" group-title="Italy",Rai 1
https://d3k8wzt41aflvx.cloudfront.net/RAI1/Live.m3u8
#EXTINF:-1 tvg-logo="https://i.imgur.com/zA0PTcs.png" group-title="Italy",Rai 2
https://d3k8wzt41aflvx.cloudfront.net/RAI2/Live.m3u8
#EXTINF:-1 tvg-logo="https://i.imgur.com/9kuQCIi.png" group-title="Italy",Rai 3
https://d3k8wzt41aflvx.cloudfront.net/RAI3/Live.m3u8
#EXTINF:-1 tvg-logo="https://i.imgur.com/F90mpSa.png" group-title="Italy",La7
https://d1chghleocc9sm.cloudfront.net/v1/master/3722c60a815c199d9c0ef36c5b73da68a62b09d1/cc-evfku205gqrtf/Live.m3u8
#EXTINF:-1 tvg-logo="https://i.imgur.com/Hp723RU.png" group-title="Italy",Nove
https://streaming.aurora.enhanced.live/live/mpc/enl0eG1mLmVncmVzcy5mZDJ2eHI=/out/v1/IT_SIMULCAST/NOVE/CMAF/index.m3u8
#EXTINF:-1 tvg-logo="https://i.imgur.com/RKI4nFy.png" group-title="Italy",Rai Premium
https://d3k8wzt41aflvx.cloudfront.net/RaiPremium/Live.m3u8
#EXTINF:-1 tvg-logo="https://i.imgur.com/x7RaK3a.png" group-title="Italy",TV 2000
https://hls-live-tv2000.akamaized.net/hls/live/2028510/tv2000/master.m3u8
#EXTINF:-1 tvg-logo="https://i.imgur.com/9dcTYg1.png" group-title="Italy",Real Time
https://streaming.aurora.enhanced.live/live/mpc/enl0eG1mLmVncmVzcy5mZDJ2eHI=/out/v1/IT_SIMULCAST/REALTIME/CMAF/index.m3u8
#EXTINF:-1 tvg-logo="https://upload.wikimedia.org/wikipedia/commons/thumb/6/63/Belsat_%282022%29.svg/960px-Belsat_%282022%29.svg.png" group-title="Poland",Belsat
https://iptv.prosto.tv/ch171/index.m3u8
#EXTINF:-1 tvg-logo="https://i.imgur.com/2JO5Y8c.png" group-title="Poland",4 Fun Kids (576i) Ⓢ
https://stream.4fun.tv:8889/hls/4fk.m3u8
#EXTINF:-1 tvg-logo="https://provider-static.plex.tv/epg/cms/production/5d4ac35c-dd3f-4f56-a272-41ebfe3477a9/american_crime_channel_dark_logo_-_Kam_JeyRDXV2.png" group-title="Poland",American Crime Channel
https://d39g1vxj2ef6in.cloudfront.net/v1/master/3fec3e5cac39a52b2132f9c66c83dae043dc17d4/prod-rakuten-stitched/master.m3u8?ads.xumo_channelId=88883104
#EXTINF:-1 tvg-logo="https://btk.bsmbialogard.pl/sites/default/files/inline-images/logo%20header2%282%29.png" group-title="Poland",Bialogardzka Telewizja Kablowa (1080p)
https://bsmbialogard.pl/live/index.m3u8
#EXTINF:-1 tvg-logo="https://images-3.rakuten.tv/storage/global-live-channel/translation/artwork/1fe37ff8-c6b7-4123-8c68-653d657b4c5f-width200-quality90.jpeg" group-title="Poland",Bigtime Ⓢ
https://103f01c3ff79408e83c9212f8a374ecc.mediatailor.us-east-1.amazonaws.com/v1/master/0fb304b2320b25f067414d481a779b77db81760d/RakutenTV-eu_BjgtjmeDarmoweFilmy/playlist.m3u8
#EXTINF:-1 tvg-logo="https://i.imgur.com/C5g0ejM.png" group-title="Poland",BTB 2 (1080p)
https://emisja.btb.j00r.us/iptv/session/2/hls.m3u8
#EXTINF:-1 tvg-logo="https://btb.j00r.us/images/logo_BTB.webp" group-title="Poland",BTB (1080p)
https://emisja.btb.j00r.us/iptv/session/1/hls.m3u8
#EXTINF:-1 tvg-logo="https://i.imgur.com/U8mcRal.png" group-title="Poland",BTB HD (720p)
https://emisja.btb.j00r.us/iptv/session/1/live.m3u8
"""


def read(source):
    """Playlist text from a local path or an http(s) URL."""
    if source.startswith(("http://", "https://")):
        req = urllib.request.Request(source, headers={"User-Agent": UA})
        with urllib.request.urlopen(req, timeout=TIMEOUT) as r:
            return r.read(MAX_PLAYLIST).decode("utf-8", errors="replace")
    with open(source, encoding="utf-8", errors="replace") as f:
        return f.read(MAX_PLAYLIST)


def parse(text):
    """Return [{name, url, group, logo, id}], in playlist order."""
    channels = []
    meta = {}
    group = ""
    for raw in text.splitlines():
        line = raw.strip()
        if not line:
            continue
        if line.startswith("#EXTM3U"):
            continue
        if line.startswith("#EXTINF:"):
            attrs = dict(ATTR.findall(line))
            # the display name follows the first comma; without one there is no
            # name, and tvg-name is the fallback (rsplit returned the attributes)
            name = line.split(",", 1)[1].strip() if "," in line else ""
            meta = {
                "name": name or attrs.get("tvg-name", ""),
                "group": attrs.get("group-title", "") or group,
                "logo": attrs.get("tvg-logo", ""),
                "id": attrs.get("tvg-id", ""),
            }
            continue
        if line.startswith("#EXTGRP:"):
            group = line[len("#EXTGRP:") :].strip()
            continue
        if line.startswith("#"):
            continue
        if not meta:
            # a bare URL without EXTINF is still a channel
            meta = {
                "name": line.rsplit("/", 1)[-1],
                "group": group,
                "logo": "",
                "id": "",
            }
        channel = dict(meta)
        channel["url"] = line
        if channel["name"] and channel["url"]:
            channels.append(channel)
        meta = {}
    return channels


def main(argv):
    if len(argv) != 2:
        print(json.dumps({"error": "usage: live-tv.py <playlist path or URL>"}))
        return 0
    try:
        channels = parse(FREE_M3U if argv[1] == "defaults" else read(argv[1]))
        if not channels:
            print(json.dumps({"error": "No channels in that playlist"}))
        else:
            print(json.dumps(channels))
    except (OSError, ValueError, urllib.error.URLError) as exc:
        print(json.dumps({"error": str(exc) or "The playlist could not be read"}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
