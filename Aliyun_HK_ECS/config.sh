## Version: v2.8.0
## Date: 2021-06-20
## Update Content: 可持续发展纲要\n1. session管理破坏性修改\n2. 配置管理可编辑config下文件\n3. 自定义脚本改为查看脚本\n4. 移除互助相关

## 上面版本号中，如果第2位数字有变化，那么代表增加了新的参数，如果只有第3位数字有变化，仅代表更新了注释，没有增加新的参数，可更新可不更新

## 在运行 ql repo 命令时，是否自动删除失效的脚本与定时任务
AutoDelCron="true"

## 在运行 ql repo 命令时，是否自动增加新的本地定时任务
AutoAddCron="true"

## 拉取脚本时默认的定时规则，当匹配不到定时规则时使用，例如: 0 9 * * *
DefaultCronRule=""

## ql repo命令拉取脚本时需要拉取的文件后缀，直接写文件后缀名即可
RepoFileExtensions="js py ts sh"

## 代理地址，支持HTTP/SOCK5，例如 http://127.0.0.1:7890
ProxyUrl=""

## 资源告警阙值，默认CPU 80%、内存80%、磁盘90%
CpuWarn=100
MemoryWarn=90
DiskWarn=90

## 设置定时任务执行的超时时间，默认1h，后缀"s"代表秒(默认值), "m"代表分, "h"代表小时, "d"代表天
CommandTimeoutTime="1h"

## 设置批量执行任务时的并发数，默认同时执行5个任务
MaxConcurrentNum="5"

## 在运行 task 命令时，随机延迟启动任务的最大延迟时间
## 默认给javascript任务加随机延迟，如 RandomDelay="300" ，表示任务将在 1-300 秒内随机延迟一个秒数，然后再运行，取消延迟赋值为空
RandomDelay="300"

## 需要随机延迟运行任务的文件后缀，直接写后缀名即可，多个后缀用空格分开，例如: js py ts
## 默认仅给javascript任务加随机延迟，其它任务按定时规则准点运行。全部任务随机延迟赋值为空
RandomDelayFileExtensions="js"

## 每小时的第几分钟准点运行任务，当在这些时间运行任务时将忽略 RandomDelay 配置，不会被随机延迟
## 默认是第0分钟和第30分钟，例如21:00或21:30分的任务将会准点运行。不需要准点运行赋值为空
RandomDelayIgnoredMinutes="0 30"

## 如果你自己会写shell脚本，并且希望在每次运行 ql update 命令时，额外运行你的 shell 脚本，请赋值为 "true"，默认为true
EnableExtraShell="true"

## 是否自动启动bot，默认不启动，设置为true时自动启动，目前需要自行克隆bot仓库所需代码，存到ql/repo目录下，文件夹命名为dockerbot
AutoStartBot=""

## 是否使用第三方bot，默认不使用，使用时填入仓库地址，存到ql/repo目录下，文件夹命名为diybot
BotRepoUrl=""

## 安装python依赖时指定pip源
PipMirror="https://pypi.doubanio.com/simple/"

## 安装node依赖时指定npm源
NpmMirror="https://registry.npmmirror.com"

## 通知环境变量
## 1. Server酱
## https://sct.ftqq.com
## 下方填写 SCHKEY 值或 SendKey 值
export PUSH_KEY=""

## 2. BARK
## 下方填写app提供的设备码，例如：https://api.day.app/123 那么此处的设备码就是123
export BARK_PUSH=""
## 下方填写推送图标设置，自定义推送图标(需iOS15或以上)
export BARK_ICON="https://qn.whyour.cn/logo.png"
## 下方填写推送声音设置，例如choo，具体值请在bark-推送铃声-查看所有铃声
export BARK_SOUND=""
## 下方填写推送消息分组，默认为"QingLong"
export BARK_GROUP="QingLong"

## 3. Telegram
## 下方填写自己申请@BotFather的Token，如10xxx4:AAFcqxxxxgER5uw
export TG_BOT_TOKEN="5853818580:AAESWHk82Y917vmntg4mHLzru4k0BRP-bzc"
## 下方填写 @getuseridbot 中获取到的纯数字ID
export TG_USER_ID="5761114110"
## Telegram 代理IP（选填）
## 下方填写代理IP地址，代理类型为 http，比如您代理是 http://127.0.0.1:1080，则填写 "127.0.0.1"
## 如需使用，请自行解除下一行的注释
export TG_PROXY_HOST=""
## Telegram 代理端口（选填）
## 下方填写代理端口号，代理类型为 http，比如您代理是 http://127.0.0.1:1080，则填写 "1080"
## 如需使用，请自行解除下一行的注释
export TG_PROXY_PORT=""
## Telegram 代理的认证参数（选填）
export TG_PROXY_AUTH=""
## Telegram api自建反向代理地址（选填）
## 教程：https://www.hostloc.com/thread-805441-1-1.html
## 如反向代理地址 http://aaa.bbb.ccc 则填写 aaa.bbb.ccc
## 如需使用，请赋值代理地址链接，并自行解除下一行的注释
export TG_API_HOST=""

## 4. 钉钉
## 官方文档：https://developers.dingtalk.com/document/app/custom-robot-access
## 下方填写token后面的内容，只需 https://oapi.dingtalk.com/robot/send?access_token=XXX 等于=符号后面的XXX即可
export DD_BOT_TOKEN=""
export DD_BOT_SECRET=""

## 5. 企业微信机器人
## 官方说明文档：https://work.weixin.qq.com/api/doc/90000/90136/91770
## 下方填写密钥，企业微信推送 webhook 后面的 key
export QYWX_KEY=""

## 6. 企业微信应用
## 参考文档：http://note.youdao.com/s/HMiudGkb
## 下方填写素材库图片id（corpid,corpsecret,touser,agentid），素材库图片填0为图文消息, 填1为纯文本消息
export QYWX_AM=""

## 7. iGot聚合
## 参考文档：https://wahao.github.io/Bark-MP-helper
## 下方填写iGot的推送key，支持多方式推送，确保消息可达
export IGOT_PUSH_KEY=""

## 8. Push Plus
## 官方网站：http://www.pushplus.plus
## 下方填写您的Token，微信扫码登录后一对一推送或一对多推送下面的token，只填 PUSH_PLUS_TOKEN 默认为一对一推送
export PUSH_PLUS_TOKEN=""
## 一对一多推送（选填）
## 下方填写您的一对多推送的 "群组编码" ，（一对多推送下面->您的群组(如无则新建)->群组编码）
## 1. 需订阅者扫描二维码 2、如果您是创建群组所属人，也需点击“查看二维码”扫描绑定，否则不能接受群组消息推送
export PUSH_PLUS_USER=""

## 9. go-cqhttp
## gobot_url 推送到个人QQ: http://127.0.0.1/send_private_msg  群：http://127.0.0.1/send_group_msg
## gobot_token 填写在go-cqhttp文件设置的访问密钥
## gobot_qq 如果GOBOT_URL设置 /send_private_msg 则需要填入 user_id=个人QQ 相反如果是 /send_group_msg 则需要填入 group_id=QQ群
## go-cqhttp相关API https://docs.go-cqhttp.org/api
export GOBOT_URL=""
export GOBOT_TOKEN=""
export GOBOT_QQ=""

## 10. gotify
## gotify_url 填写gotify地址,如https://push.example.de:8080
## gotify_token 填写gotify的消息应用token
## gotify_priority 填写推送消息优先级,默认为0
export GOTIFY_URL=""
export GOTIFY_TOKEN=""
export GOTIFY_PRIORITY=0

## 11. PushDeer
## deer_key 填写PushDeer的key
export DEER_KEY=""

## 12. Chat
## chat_url 填写synology chat地址，http://IP:PORT/webapi/***token=
## chat_token 填写后面的token
export CHAT_URL=""
export CHAT_TOKEN=""

## 13. aibotk
## 官方说明文档：http://wechat.aibotk.com/oapi/oapi?from=ql
## aibotk_key (必填)填写智能微秘书个人中心的apikey
export AIBOTK_KEY=""
## aibotk_type (必填)填写发送的目标 room 或 contact, 填其他的不生效
export AIBOTK_TYPE=""
## aibotk_name (必填)填写群名或用户昵称，和上面的type类型要对应
export AIBOTK_NAME=""

## 其他需要的变量，脚本中需要的变量使用 export 变量名= 声明即可
## 微定制组队瓜分-jd_wdz.js
export jd_wdz_activityId="d48c5954d734418b977e779c2d8d0a9b"

## 微定制组队瓜分-jd_wdz.js
export jd_wdz_activityId="60934b326e484e818e34a6255670ad85"
## 入会开卡领取礼-jd_OpenCard_Force.js
export VENDER_ID="1000448096"
## 微定制组队瓜分-jd_wdz.js
export jd_wdz_activityId="efb5400a99e343fe9b65f207bf3531be"
## 微定制组队瓜分-jd_wdz.js
export jd_wdz_activityId="a16e4cfe5f4b4b4faace802fa7e5b875"
export DPLHTY="5ea636547445492e8_230101"

#🚨 邀请入会赢好礼 · 京耕
export jd_showInviteJoin_activityUrl="https://jinggeng-isv.isvjcloud.com/ql/front/showInviteJoin?id=9e8080798560f5620185679179fa1837&user_id=11651921"

#🚨 邀请入会有礼 · 超级无线欧莱雅
export jd_lzkj_loreal_invite_url="https://lzkj-isv.isvjcloud.com/prod/cc/interactsaas/index?activityType=10070&templateId=20201228083300yqrhyl01&activityId=1608757807990644737"

##通用抽奖机-jd_lottery.js
export JD_Lottery="a1ded223358846c287b4178ef8ed4103"

#🎁 店铺礼包 · 超级无线
export jd_wxShopGift_activityUrl="https://lzkj-isv.isvjd.com/wxShopGift/activity?activityId=2817c2bf2c6540c18577497d529f5d2c"

## CJ组队瓜分-jd_cjzdgf.js
export jd_cjhy_activityId="605d03c6ca804627b6ecf681654de402"

#🎁 店铺礼包 · 超级无线
export jd_wxShopGift_activityUrl="https://lzkj-isv.isvjd.com/wxShopGift/activity?activityId=be90f00b29f64703946c0719ba99d2bc"

export JD_Lottery="c2f5cd8e10a14d97b4e5d77f0eb52487"

#📆 店铺签到 · 超级无线
export jd_shopSign_activityUrl="https://lzkj-isv.isvjcloud.com/sign/signActivity2?activityId=fc13ebe0a2ad4c9991faba8d3ff06989"

#🚨 邀请入会赢好礼 · 京耕
export jd_showInviteJoin_activityUrl="https://jinggeng-isv.isvjcloud.com/ql/front/showInviteJoin?id=9e8080ad8599a94f01859aabe24d47ee&user_id=11651921"

#【CJ微定制】
export jd_wdz_activityId="101c52274ef34463bed16bed0bdee930"

### 品类联合
export jd_categoryUnion_activityId="5213bdfdb5774dc788b4246022288048"

#【CJ微定制】
export jd_wdz_activityId="ffb6703766df4dcf90e475822479fc26"

#🚨 邀请入会有礼 · 超级无线欧莱雅
export jd_lzkj_loreal_invite_url="https://lzkj-isv.isvjcloud.com/prod/cc/interactsaas/index?activityType=10070&templateId=7fab7995-298c-44a1-af5a-f79c520fa8a888&activityId=1619172009963343873&nodeId=101001"

#🎀 关注店铺有礼 · 超级无线
export jd_wxShopFollowActivity_activityUrl="https://lzkj-isv.isvjcloud.com/wxShopFollowActivity/activity/activity?activityId=1618aecd9afd4ea282788737bdb667d3"

### 微定制组队瓜分-jd_wdz.js
export jd_wdz_activityId="97810c54192345c09227cbf0738ab425"
## 品类联合
export jd_categoryUnion_activityId="fd852921a9394367a86dc4c3fff6a1c6"

## 微定制组队瓜分-jd_wdz.js
export jd_wdz_activityId="e74c1e10b60e48f5b8e2cee8b74cb21e"

## 微定制组队瓜分-jd_wdz.js
export jd_wdz_activityId="3a1bb15f92c94e1ca3ff288a23010597"