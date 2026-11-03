# 線上無人島商圈

目前版本：V12 單頁遊戲，已加入 Supabase Auth、店面雲端資料、Realtime 玩家同步、帳號私訊與公園設備鎖定。正式使用前需先套用 SQL 並完成 Supabase Auth provider 設定。

## 開啟與維護

```sh
npm start
```

瀏覽 http://127.0.0.1:4178/?v=12 。已開啟的舊頁需重新整理。

```sh
npm install
npm run format
```

Prettier 僅用於開發時排版，網頁執行不需要它。

## 程式碼導覽

`index.html` 保留單檔，避免改變既有啟動及離線開啟方式；HTML、CSS、JavaScript 已統一縮排。主畫面含平台公告與未接廣告服務的版位預留；店主可在每項商品、作品或職缺設定最多 10 個外部購買／聯絡網址，訪客在項目詳情中可直接開啟。舊版店鋪引流網址會在店主下次儲存店舖設定時移入尚未設定外連的項目。搜尋以下函式可快速找到功能：

| 區塊 | 函式 |
| --- | --- |
| 室外地圖、人物與店面 | drawTown、drawStore、moveStreet |
| 搜尋與店面列表 | renderShopList、shopType |
| 室內畫面、移動與相框 | drawInterior、updateInterior、openProductDetails |
| 租借、退租及店鋪設定 | openRental、endLease、renderEditor |
| 商品／作品登記 | openRegister、validateListing。每個項目可設定最多 10 個外部購買／作品／聯絡網址，訪客在詳情中開啟 |
| 徵才登記 | openJobRegister、validateJob。休假制度與可上班日提供常用選項及「其他」自填；條件逐筆新增、刪除並自動編號；薪資可填範圍或單一金額；上班時間可直接輸入或選擇後按鈕確認；工作照片選填；職缺可附最多 10 個履歷投遞／聯絡網址 |
| LOGO 與看板 | initBoardDesign、paintBoard |
| 本機媒體儲存 | saveMediaBlob、mediaUrlFor、deleteMediaBlob |
| 店內音樂 | loadShopMusic、uploadShopMusic、removeShopMusic。每店單首循環；須已登入並上傳有公開播放授權的音檔，最多 10 MB，存入 Supabase Storage 供其他訪客播放。 |
| 店面座標與防重疊 | syncShopPositions、placementValidity、enforce_market_shop_non_overlap |

`preview-server.cjs`：本機網頁伺服器。

## 上傳 GitHub

保留根目錄的程式、套件設定、README、排版設定、SQL 與 Supabase Functions。測試腳本已移除，遊戲執行不需要它們。

`node_modules` 可用 `npm ci` 重建，不需上傳。不要提交 `.env`、金鑰或本機日誌；已在 `.gitignore` 排除。使用者在瀏覽器中建立的店面與媒體不在此資料夾，也不會隨原始碼提交。

上傳原始碼不會自動部署；正式多人連線、登入和資料權限需要 Supabase SQL、Auth provider 與 Vercel 部署設定完成。

## V12 媒體政策

- 新相框僅上傳圖片；影片改填外部網址，不下載或保存外部影片檔案。
- 禁止新影片檔案進入媒體儲存；圖片、徵才照片、LOGO 和單曲音樂功能保留。
- 已有影片不自動刪除，編輯時可選擇保留原有影片、改用網址或不放影片。
- 外部平台若不允許內嵌，使用既有原站連結觀看。
- 遊戲不接受影片檔上傳；請貼外部影片網址。未附圖片時，YouTube 連結使用其影片公開縮圖，其他影片來源使用 `assets/video-link-landscape.svg` 或 `assets/video-link-vertical.svg` 通用預覽，不複製未授權的平台商標。尷尬笑臉說明圖為 `assets/awkward-smile.svg`。
- 店面資料存在 Supabase 與瀏覽器快取；作品／徵才上傳的圖片與店主單曲音樂存入 Supabase Storage。音樂最多 10 MB，透過 TUS 分段上傳、斷線重試與進度顯示，僅限店主確認有權公開播放的音檔；訪客進入展廳後嘗試自動播放，離店停止。瀏覽器可能要求先有一次使用者操作才允許播放聲音。音樂由 Supabase 公開 bucket 串流，會產生 egress；更換或移除單曲會清理舊雲端音檔。YouTube 音訊不能抽離成隱藏背景播放；Spotify Widget 不作為店面背景音樂來源。
- 主畫面公告說明平台只提供展示及導流；右側廣告方塊目前只是版位預留，尚未連接廣告網路或追蹤碼。

## 給下一個對話的交接

請先讀本 README，再針對新需求查看相關函式。既有功能包括俯視島嶼、第一人稱展廳、店面分類、徵才、相框、音樂、LOGO、兩座公園與自行車。保留使用者現有資料；不需重做已完成介面。

## Supabase 接線（2026-11）

在 Supabase SQL Editor 執行 `supabase-setup.sql`。`index.html` 已填入 Project URL 與 publishable key；勿填 service_role/secret key。網頁透過 CDN 載入 Supabase JS v2。若換專案，搜尋 `SUPABASE_URL` 和 `SUPABASE_ANON_KEY` 更換。

已接入店面 JSON/租約到期時間、Auth 匿名訪客與社群帳號綁定、店主 RLS、玩家 Realtime、Storage 圖片、帳號私訊與公園設備原子鎖。位置同步採用 AOI 格子頻道；大型規模仍需市集資料分區或專用遊戲伺服器。

雲端載入時會以 Supabase 店面資料覆蓋同 ID 的本機內容。店面圖片上傳至公開 Storage bucket；媒體以外的音樂、LOGO、廣告等既有 IndexedDB 素材仍未自動遷移至 Storage。

## Auth、帳號權限與行動操作（本次更新）

先在 Supabase SQL Editor 重新執行 `supabase-setup.sql`，將舊的公開寫入政策換成店主 RLS，建立私訊與公園設備鎖定資料表/RPC。到 Supabase Authentication 設定開啟 **Anonymous Sign-ins**，設定 Site URL 為 `https://gmae-viastudio.vercel.app`，並將 `https://gmae-viastudio.vercel.app/**`、`http://127.0.0.1:4178/**`、`http://localhost:4178/**` 加入 Redirect URLs。啟用並填入 Google、Facebook OAuth 憑證（OAuth client secret 只放 Supabase Dashboard）；電子郵件登入使用確認連結。未設定 provider 或 redirect URL 時，相應驗證流程會由 Supabase 拒絕。

使用者先以匿名訪客逛島；登入視窗直接提供 Google、Facebook 與電子郵件登入，不再要求選擇「綁定」或「登入」。第一次使用某個登入方式會建立帳號，之後使用相同方式即可回到原帳號；匿名訪客資料不會自動合併到帳號。Supabase Auth 明確設定 `persistSession`、`autoRefreshToken` 與 `detectSessionInUrl`，登入工作階段會保存在目前瀏覽器；關閉頁面再開通常仍保持登入。登出、清除網站資料、瀏覽器不保留網站儲存資料或使用其他裝置時，需重新登入。登出會撤銷原店主權限並回到新的訪客身分。資料庫的店面寫入僅允許已綁定帳號更新自己的租約，私訊僅允許對話雙方讀寫。公園設施透過原子鎖避免其他玩家搶用，15 秒租約每 5 秒續期，離開時釋放。

玩家可以在手機/平板使用街道方向鍵、互動鍵、室內方向鍵和視角旋轉按鈕；室內 Canvas 也支援拖曳轉向。NPC 會使用避開店面的格狀路徑在全地圖漫遊；若生成在建築碰撞範圍內，會自動移至最近可走位置。舊版 showcase NPC 租店會在本機載入時清空；SQL 也會清空雲端標記為 showcase 的示範租約。

## 流量保護（2026-11）

- Supabase 玩家位置使用 600 像素格子的 AOI 頻道；每位玩家訂閱所在格及周圍八格，並精確篩到 600 像素。畫面最多繪製最近 20 位玩家。
- 雲端走動位置最長每 250 毫秒送一次，且至少移動 6 像素才送；Presence 只在進入新格時更新，不再定時重送座標。這會減少位置廣播量，但不會降低同一 Supabase 專案的同時連線上限。
- 相框商品／作品、職缺照片、店面 LOGO 與廣告圖片會在瀏覽器先等比例縮至長邊最多 2560 像素，再以 WebP 品質 0.92 至 0.86 編碼；若仍超過 2 MB，會逐步縮小到長邊 1280 像素後停止，盡量兼顧畫質與檔案大小（實際大小依照片內容而異）；每間店的商品、作品與徵才圖片合計最多 5 張 Supabase Storage 圖片。原始檔不會被改寫；重新編碼與縮圖可能略微降低畫質，請保留原始照片備份。解析度極高的來源圖（單邊超過 10000px 或總像素超過 5000 萬）會提示先縮小後再上傳。
- 公開圖片使用隨機且不覆寫的 Storage 路徑，設定 `cacheControl: 86400`（瀏覽器快取 24 小時），並由 Supabase Storage CDN 提供。CDN 快取命中不代表傳輸量歸零，也不能保證永遠命中；Free 方案仍須同時監控快取與未快取 Egress。Supabase Smart CDN 自動重新驗證屬 Pro 以上功能；目前的快取設定不代表已啟用 Smart CDN。
- `supabase-setup.sql` 已包含圖片數量保護；既有專案可另外執行 `traffic-protection.sql` 套用同一保護與到期掃描索引。這些 SQL 不會刪除現有資料；若某店原本已超過 5 張，可以繼續修改或刪圖，但不能增加圖片數量。
- A/B/C 市集分區尚未接入。現在的 AOI 只減少位置訊息扇出，店面仍在同一 `market_shops` 資料表，Realtime 連線仍共用同一 Supabase 專案額度。要做真正的市集隔離，需另加 `market_id` 欄位、分區查詢/RLS、店面座標防重疊分區與市集選單，再將既有資料指定到其中一區。
- 瀏覽圖片仍會產生 Storage 流量；壓縮會降低單張大小，不能把已用掉的流量「補回」。這些變更是節流與容量保護，不代表可以支撐數萬至百萬同時在線玩家。

## 店面一次性清空與街道操作

`reset-game-data.sql` 會清空 Supabase 店面租約、介紹、商品、佈置、私訊與公園占用狀態，同時保留店面 ID 與地圖位置，供玩家重新租用。這是不可逆的資料變更。SQL 會在空店面留下重設版本標記；更新後的遊戲第一次連到雲端時，會清除該瀏覽器的舊店面、訂單、角色設定與媒體快取。要立即清除目前瀏覽器，也可用 `?resetShops=1` 開啟一次。帳號登入本身與遊戲程式保留。

街道地圖可單點目的地自動前往；在空地按住滑鼠或手指並移動，人物會持續追蹤指標並改變方向。室內 360° 滑鼠環視按鈕固定在遊戲畫面右側中央。

## 店面重疊與登入錯誤修復（2026-11）

index.html 載入雲端店面時會為缺少座標或互相重疊的資料重新安排位置，並在本機存檔。店面放置檢查會拒絕與其他建築或店面重疊；為防止多人同時選到同一位置，請在 Supabase SQL Editor 執行 shop-layout-guard.sql。現有正式專案若已套用舊版重疊觸發器，還需執行 shop-overlap-trigger-fix.sql：它只在新增店面或真的變更座標時檢查重疊，允許音樂、商品、聯絡方式等其他欄位正常保存，不會更改店面資料或座標。之後初始化新環境也可執行已含修正版觸發器的 supabase-setup.sql。

若登入回呼顯示 identity_already_exists，代表該 Google/Facebook 身分已屬於既有 Supabase 使用者；請使用同一供應商登入。訪客資料不會自動合併到既有帳號。登入回呼讀取失敗時，遊戲會顯示實際錯誤，不會靜默假裝登入成功。

## 續租與租期到期清理（2026-11）

在 Supabase SQL Editor 先執行 supabase-setup.sql，再執行 shop-layout-guard.sql。店主在自己的店內可按「續租」，選 7、14 或 15 天；資料庫 RPC 會驗證登入帳號、店主權限與天數，並把新到期時間寫入 market_shops.expire_at 與店面 lease。

到期後，瀏覽器會立即清理當前裝置的店面快取、商品、訂單與 IndexedDB 媒體。伺服器端清理需另外部署 supabase/functions/expire-shops/index.ts，並套用 shop-expiry-cron.sql。Edge Function 會透過 Storage API 刪除店主資料夾內該店的圖片，清掉私訊及店面內容，保留空店格與地圖座標。排程每分鐘執行一次，處理中會暫停該店重新出租；成功後其他玩家可租。其他裝置上的本機 IndexedDB 快取只會在該裝置再次開啟遊戲時清除。

部署 Edge Function 前，在 Supabase Edge Function Secrets 設定 EXPIRE_SHOPS_CRON_SECRET；在 Supabase Vault 建立 project_url、publishable_key、expire_shops_cron_secret 三筆秘密，最後執行 shop-expiry-cron.sql。project_url 填專案 URL，publishable_key 填 Supabase 公開 Publishable key，expire_shops_cron_secret 填與 Edge Function secret 完全相同的隨機長字串。service-role/secret key 由 Supabase 注入 Edge Function 執行環境，不要放進 SQL、瀏覽器或 GitHub。Edge Function 不會隨 Vercel 部署，需另用 Supabase CLI 執行 npx supabase functions deploy expire-shops --project-ref cfokmnfzpcqgenueivex。

## 免費方案檢查

遊戲程式沒有信用卡付款、Stripe、Checkout 或任何向玩家收款的整合；產品標價只用於展示，不會在遊戲內扣款。Supabase 的 Free 用量有上限，超過時會受服務限制；此版本的每分鐘清理排程約每月呼叫 Edge Function 43,200 次，仍低於目前 Free 配額，但資料庫、儲存、流量與 Realtime 仍須留意使用量。免費 Supabase 專案可能因長期低活動而暫停。Vercel Hobby 免費方案限制個人非商業用途；若商圈用於實際商業營運，需先確認 Vercel 條款是否允許。
