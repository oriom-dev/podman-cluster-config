# 日本郵便APIプロキシサーバー

日本郵便は、郵便番号から住所を検索するための公式のAPIを提供しています。

APIは、事前に発行したclient idとclient secretでアクセス可能ですが、発行の際にはサーバーの固定ipが必要で、そのipからのアクセスしか許可されません。

このシステムは固定IPを持つVPS上などに置かれ、APIリクエストを中継します。

PROXY_AUTH_TOKENに指定されたトークンをAuthorizationヘッダーに含めてリクエストすることで、APIを利用できます。

- リクエストヘッダー: `Authorization: Bearer <PROXY_AUTH_TOKEN>`
- 検索コード形式: 英数字7文字（郵便番号・デジタルアドレス）

## 必須環境変数

- `PROXY_AUTH_TOKEN`
- `JPOST_CLIENT_ID`
- `JPOST_CLIENT_SECRET`

## scripts

```
npm install
npm run dev
```
