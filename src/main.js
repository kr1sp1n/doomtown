
function main () {
  let header = `<!DOCTYPE html><html><head>
    <title>doomtown.cc</title>
    <style>
      * {
        margin: 0;
        padding: 0;
      }

      body {
        background: #333;
        font-family: monospace, courier;
        font-size: 14px;
        line-height: 16px;
      }

      .header {
        margin: 16px 0 0 0;
      }

      .logo {
        display: block;
        margin-left: auto;
        margin-right: auto;
        image-rendering: pixelated;
      }

      .content {
        background: #fff;
        border-left: 2px solid black;
        border-right: 2px solid black;
        width: 624px;
        margin: 0 auto 0 auto;
      }

      @media (max-width: 623px ) {
        body {
          font-size: 12px;
          line-height: 14px;
        }
        .content {
          width: 312px;
          border-left: 1px solid black;
          border-right: 1px solid black;
        }
      }

      .content h1 {
        text-align: center;
        color: #666;
      }

      .content h2 {
        padding: 16px 16px 0 16px;
      }

      .content p {
        padding: 8px 16px 16px 16px;
      }

    </style>
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <link rel="alternate" type="application/rss+xml" title="RSS" href="http://localhost:3000/rss.xml" />
  </head><body>
  <div class="header">
    <picture>
      <source media="(max-width: 623px)" srcset="img/doomtown_header_002_312px.png" />
      <source media="(min-width: 624px)" srcset="img/doomtown_header_002_624px.png" />
      <img class="logo" src="img/doomtown_header_002_624px.png" alt="doomtown.cc" />
    </picture>
  </div>`

  let content = `<div class="content">
    <h1>Local Area Network</h1>
    <h2>Testüberschrift</h2>
    <p>LOL WTF ksdhfkjsdhfkjsdkjfhjkshdf kfgkjdfg kjdfg kjdfjksdhfkjsd kjh fkjs hdjkfkjsdhfkjshdjkfhkjsdhfjkshdjkf
    kdfhgjkdfhgjk kdhfg khjkg dfkjg kjd gkjhdf kghdjkfg.
    </p>
  </div>`
  let footer = '</body></html>'

  const output = `${header}${content}${footer}`
  console.log(output)
}

main()