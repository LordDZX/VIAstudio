# 線上無人島商圈

目前版本：V12。這是本機互動原型，尚未接正式帳號、雲端儲存或跨裝置多人伺服器。

## 開啟與維護

```sh
npm start
```

瀏覽 http://127.0.0.1:4178/?v=12 。已開啟的舊頁需重新整理。

```sh
npm install
npm run format
npm test
```

Prettier 僅用於開發時排版，網頁執行不需要它。`npm test` 會依序執行全部版本的回歸測試，任何一項失敗就停止。

## 程式碼導覽

`index.html` 保留單檔，避免改變既有啟動及離線開啟方式；HTML、CSS、JavaScript 已統一縮排。搜尋以下函式可快速找到功能：

| 區塊 | 函式 |
| --- | --- |
| 室外地圖、人物與店面 | drawTown、drawStore、moveStreet |
| 搜尋與店面列表 | renderShopList、shopType |
| 室內畫面、移動與相框 | drawInterior、updateInterior、openProductDetails |
| 租借、退租及店鋪設定 | openRental、endLease、renderEditor |
| 商品／作品登記 | openRegister、validateListing |
| 徵才登記 | openJobRegister、validateJob |
| LOGO 與看板 | initBoardDesign、paintBoard |
| 本機媒體儲存 | saveMediaBlob、mediaUrlFor、deleteMediaBlob |
| 音樂 | loadShopMusic、uploadShopMusic |

`preview-server.cjs`：本機網頁伺服器。`run-tests.cjs`：統一測試入口。

## 上傳 GitHub

保留根目錄的程式、套件設定、README、排版設定與測試檔。`test-v4.cjs` 至 `test-v12.cjs` 雖然以版本命名，仍驗證目前功能，並非過期備份。

`node_modules` 可用 `npm ci` 重建，不需上傳。不要提交 `.env`、金鑰或本機日誌；已在 `.gitignore` 排除。使用者在瀏覽器中建立的店面與媒體不在此資料夾，也不會隨原始碼提交。

上傳原始碼不會自動提供正式多人服務；目前沒有正式登入或後端權限驗證。

## V12 媒體政策

- 新相框僅上傳圖片；影片改填外部網址，不下載或保存外部影片檔案。
- 禁止新影片檔案進入媒體儲存；圖片、徵才照片、LOGO 和音樂功能保留。
- 已有影片不自動刪除，編輯時可選擇保留原有影片、改用網址或不放影片。
- 外部平台若不允許內嵌，使用既有原站連結觀看。
- 媒體目前存在瀏覽器 IndexedDB，店面資料存在 localStorage；清除瀏覽器資料可能使內容遺失。分頁同步不代表跨裝置正式多人連線。

## 給下一個對話的交接

請先讀本 README，再針對新需求查看相關函式。既有功能包括俯視島嶼、第一人稱展廳、租店權限原型、店面分類、徵才、相框、音樂、LOGO、兩座公園與自行車。保留使用者現有資料；不需重做已完成介面。正式登入、後端權限、共用媒體及大規模多人架構仍未實作。

## Supabase 原型接線（2026-11）

在 Supabase SQL Editor 執行 `supabase-setup.sql`。接著開啟 `index.html`，搜尋 `SUPABASE_URL` 和 `SUPABASE_ANON_KEY`（在主 `<script>` 開頭附近），填入 Project URL 與 anon/publishable key；勿填 service_role key。網頁透過 CDN 載入 Supabase JS v2。尚未設定時會維持原本本機模式。

已接入店面 JSON/租約到期時間、玩家座標 Realtime、租期內作品／職缺到期欄位、Storage 圖片公開 URL，以及資料庫私訊載入與即時訂閱。地圖只繪製 600 像素內玩家；目前共用 Presence topic 仍會將 presence 狀態送到所有連線，若要承受大量在線玩家，需改成伺服器端 3×3 cell topic 訂閱或專用遊戲伺服器。此版本尚未做 Supabase Auth；SQL prototype policies 對 anon 開放，任何人都可讀寫店面和私訊，不能作為公開正式服務。上線前必須加入登入、owner/participant 權限 RLS 與可信任的租約驗證。

雲端載入時會以 Supabase 店面資料覆蓋同 ID 的本機內容。店面圖片上傳至公開 Storage bucket；媒體以外的音樂、LOGO、廣告等既有 IndexedDB 素材仍未自動遷移至 Storage。
