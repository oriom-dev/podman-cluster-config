# AppView BSAF収集の許可元と本番確認

2026-10-18、利用者の指定により以下の発信元を許可した。

- ハンドル: `jma-alert-bot.bsky.social`
- 固定したDID: `did:plc:vwi7zhfyamyvrg5v6ycjgzxi`
- 確認: `com.atproto.identity.resolveHandle`の結果と、PLC DID Documentの
  `alsoKnownAs: at://jma-alert-bot.bsky.social`が対応することを確認。
- Botの表示名は「気象庁 地震・火山・津波Bot（非公式）」。
  この許可は気象庁による認証・公的機関への帰属認定ではない。

許可リストは`hosts/kagoya_vps/default.nix`の`services.mosimo-bsaf.authors`。
他のBotは追加していない。情報種別による選別はせず、このBotの`bsaf:v1`投稿を収集する。
Mosimoへの変換、Nostr・メッシュへの再配信、自動の新規投稿は有効にしていない。

## 反映と検証

- 使用する実装入力は引き続き`61e1247813c468e7ec5c9ea91c56709aea001c9c`。
- system closure:
  `/nix/store/a6s3n8xi00y19y9h0r829jpbjd29l7p2-nixos-system-kagoya-vps-26.05.20260409.4c1018d`。
- 初回の検証用に、未使用のcollector cursor（NULL）だけを
  `1792288952204000`（2026-10-18 02:02:32.204 UTC）へ設定した。
  原投稿をDBへ直接投入したのではなく、Jetstream履歴から実際の収集処理を通した。
  これは一度限りの限定再生であり、一般の過去投稿backfill機能を追加したわけではない。
- `mosimo-bsaf.service`はactive/running、初回起動時NRestarts=0。
  メモリ使用量33,566,720 bytes、ピーク34,017,280 bytesを観測。
- `mosimo_bsaf_sources`は指定DIDの1件だけ。
  `happyview_records`の`app.bsky.feed.post`は同じDIDの4件だけだった。
- 4件全てについて、AppViewの`getFeed`から取得した原レコードと、DID Documentが示す
  `https://stropharia.us-west.host.bsky.network`の`com.atproto.repo.getRecord`を比較し、
  原URI・CID・全recordフィールドの一致をNodeのassertで確認した。
- 収集元は`wss://jetstream1.us-east.bsky.network/subscribe`、取得時刻は
  2026-10-18 03:11:01 UTC頃。原投稿の`createdAt`を書き換えてはいない。
- collectorの明示再起動後も4件のままで、統合feed内のURI重複はなかった。
  同じ統合一覧にはMosimo投稿も残っていた。

確認した投稿の例:

```text
at://did:plc:vwi7zhfyamyvrg5v6ycjgzxi/app.bsky.feed.post/3my4ja4f7us2t
CID: bafyreieblf2ommoszjcqy4cvsrk7jue4t4qow47p3r3wxfzxo5ag6xnjie
```

この例の原タグは`bsaf:v1`、`type:ashfall`、`value:info`、
`time:2026-10-18T02:00:00Z`、`target:jp-kyushu`、`source:jma`。
タグから未掲載の地理境界・公的認証・配送期限を生成していない。

以後は保存済みcursorからの再接続とライブ収集を継続する。
初回登録以前の全投稿を網羅していることや、未知の将来投稿の正常受信までを保証する試験ではない。
