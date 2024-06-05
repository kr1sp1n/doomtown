local fm = require "fullmoon"
local util = require "util"
local inspect = require "inspect"
local initQuery = util.fileToString("/zip/schema.sql")
local db = fm.makeStorage("doomtown.db", initQuery)

local function insertFile(data)
  return assert(db:execute([[
    INSERT INTO files (name, host, path, createdAt, updatedAt, hash, type) VALUES (?, ?, ?, ?, ?, ?, ?);
  ]], data.name, data.host, data.path, util.parseDate(''), util.parseDate(''), data.hash, data.type))
end

local function createHash(str)
  return EncodeBase64(Sha256(str))
end

-- insertFile({
--   name = "test.txt",
--   host = "",
--   path = "/shared/test.txt",
-- })

-- insertFile({
--   name = "test.mp3",
--   host = "",
--   path = "/shared/dietriffidsscifiklassiker_2023-07-23_dietriffids16scifiklassikerueberoekologischekatastrophe_wdronline.mp3",
-- })

local menu = {}
table.insert(menu, { title = 'Index', url = '/' })
table.insert(menu, { title = 'Dateien', url = '/files' })

unix.mkdir("./files/uploaded", 0777)

fm.setTemplate({"/views/", fmt = "fmt", fmg = "fmg"})

-- Serve shared files:
fm.setRoute("/shared/*", fm.serveAsset)

-- Serve uploaded files:
fm.setRoute("/uploaded/*", function (req)
  print(inspect(req.params))
  local hash = req.params.splat
  local file = assert(db:fetchOne("select * from files where hash = ?", hash))
  if (file) then
    return fm.serveResponse(200, {
      ContentType = file.type
    }, fm.getAsset("/uploaded/"..hash))
  end
end)

local function handleRequest(req, data)
  -- Get template name from req.path:
  local view = string.sub(req.path, 2, -1)
  if req.path == '/' then view = "index" end
  return fm.serveContent("layout", {
    view = view,
    menu = menu,
    data = data,
  })
end

-- check for the payload size and return 413 error if it's larger than the threshold
local function isLessThan(n) return function(l)
    return true
  -- return tonumber(l) < n
  end 
end

-- ContentLength = {isLessThan(1000000), otherwise = 413}

fm.setRoute(fm.POST{"/upload"}, function(req)
  local upload = req.params.multipart.upload
  -- for name, kind, ino, off in assert(unix.opendir("./files")) do
  --   if name ~= '.' and name ~= '..' then
  --      print(name)
  --   end
  -- end
  local type = upload.headers["content-type"]
  local hash = createHash(upload.data)
  local fd, err = unix.open('./files/uploaded/'..hash, unix.O_RDWR|unix.O_CREAT|unix.O_EXCL, 0777)
  if (err) then
    if (err:name() == "EEXIST") then
      return fm.serveResponse("Already exists.")
    end
    print(err:name())
  else
    unix.write(fd, upload.data)
    unix.close(fd)
    insertFile({
      name = upload.filename,
      host = "",
      path = "/uploaded/"..hash,
      hash = hash,
      type = type,
    })
    return fm.serveRedirect(fm.makePath("/"))
  end
end)

fm.setRoute("/", function(req)
  return handleRequest(req, data)
end)

fm.setRoute("/files", function(req)
  local result = assert(db:fetchAll[[
    SELECT * FROM files
    ORDER BY createdAt DESC;
  ]])
  local data = {
    files = result
  }
  -- print(util.dump(data))
  return handleRequest(req, data)
end)

fm.setRoute("/*", "/public/*")

fm.run()