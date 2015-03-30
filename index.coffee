Message = require './lib/message'
Store = require 'fs-memory-store'
defaultFixtureDir = process.cwd() + '/http-fixtures'
urlUtil = require 'url'
request = require 'request'
path = require 'path'
fs = require 'fs'

class Recorder
  constructor: (@options={}) ->
    @mode = @options.mode || 'record'
    @baseUrl = @options.baseUrl
    @store = new Store @options.fixtureDir || defaultFixtureDir

    @store.getUrl = (url, cb) ->
      id = urlUtil.parse(url).pathname
      @get id, cb

    @store.getUrlExact = (url, cb) ->
      id = urlUtil.parse(url).pathname
      @get id, (err, requests) ->
        throw err if err
        ret = req for req in requests when req.url == url
        cb null,  ret || null

  setBaseUrl: (@baseUrl) ->

  replay: (reqUrl, cb) ->
    throw new Error 'Replay requires a request path/url as its first param' unless reqUrl
    parsedUrl = urlUtil.parse reqUrl
    if parsedUrl.query
      @store.getUrlExact reqUrl, (err, req) =>
        throw err if err;
        @makeRequest req, cb

    else
      @store.getUrl reqUrl, (err, reqs) =>
        throw err if err;
        @makeRequest reqs.pop(), cb



  makeRequest: (req, cb) ->
    requestOpts =
      uri: urlUtil.resolve @baseUrl, req.url
      method: req.method
      headers: req.headers

    contentType = req.headers['content-type'];
    if contains(contentType, 'multipart/form-data')
      requestOpts.formData = req.body
      for fieldname of req.files
        localPath = req.files[fieldname].path
        filePath = path.resolve process.cwd(), localPath
        requestOpts.formData[fieldname] = fs.createReadStream filePath
    else if contains(contentType, 'application/x-www-form-urlencoded')
      requestOpts.form = req.body


    # delete the original content related headers and let request
    # set them itself
    delete requestOpts.headers['content-type']
    delete requestOpts.headers['content-length']

    request requestOpts, (err, response, body) ->
      return cb err if err
      cb err, response, body


  saveRequest: (req, done) ->
    id = req.path
    # check if requests for this url have already been records
    @store.get id, (err, requestBin) =>
      throw err if err
      requestBin = requestBin || []
      msg = new Message req
      msgInfo = msg.getRequestInfo()
      requestBin.push msgInfo
      @store.set id, requestBin, done

  getRequestBin: (id, cb) ->
    @store.get id, (err, bin) ->
      throw err if err
      cb(bin)

  middleware: () ->
    return (req, res, next) =>
      # Record request, use url as bin
      if @options.waitForWrite
        @saveRequest(req, next)
      else
        @saveRequest(req)
        next()



contains = (str, query) ->
  return false unless str && query
  return ~str.indexOf(query)

module.exports = Recorder


