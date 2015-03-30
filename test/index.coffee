express = require 'express'
bodyParser = require 'body-parser'
multer = require 'multer'
Recorder = require '../index'
rimraf = require 'rimraf'
expect = require 'expect.js'
request = require 'request'
fs = require 'fs'

recorder = null
servers = []
recorderOpts =
  # fixtureDir: __dirname + '/fixtures'
  fixtureDir: '/tmp/fixtures'
  waitForWrite: true
PORT = process.env.PORT || process.env.LEVER_PORT || 4080
recorderBaseUrl = "http://localhost:#{PORT}"
receiverBaseUrl = "http://localhost:#{PORT+1}"

createServer = (port, isRecorder) ->
  app = express()

  app.use bodyParser.urlencoded(extended: true)
  app.use bodyParser.json()
  app.use bodyParser.raw()
  app.use bodyParser.text()
  app.use multer {dest: '../../uploads/'}
  app.use recorder.middleware() if isRecorder
  app.use (req, res, next) ->
    # return request information so we can verify that
    # we are replaying the requests correctly
    res.json
      url : req.url
      body: req.body
      files: req.files


  server = app.listen port
  servers.push(server)

describe 'Recorder', ->
  before ->
    recorder = new Recorder recorderOpts

    # clear out fixture dir for ever cycle of tests
    rimraf.sync recorderOpts.fixtureDir
    createServer(PORT, true)
    createServer(PORT+1)


  after ->
    server.close() for server in servers

  it 'should have a store', ->
    expect(recorder.store).not.to.be undefined

  describe 'when recording a GET request', ->
    reqUrl = null
    it 'should accept the request', (done) ->
      reqOptions =
        uri: "#{recorderBaseUrl}/test1"
        qs: {box: 'share-123'}
        method: 'GET'
        headers:
          'user-agent': 'Mocha Test Runner 1.0'
          'some-custom-header': 'nom noms'
      request reqOptions, (err, response, body) ->
        response = response.toJSON();
        reqUrl = response.request.uri.path
        expect(err).to.be null
        expect(response.statusCode).to.be 200

        done()

    it 'should store the request', (done) ->
      recorder.store.getUrl reqUrl, (err, recorded) ->
        expect(err).to.be null
        expect(recorded).to.be.an 'array'
        recorded = recorded.pop()
        expect(recorded).to.eql
          httpVersion: '1.1'
          headers:
            'user-agent': 'Mocha Test Runner 1.0'
            'some-custom-header': 'nom noms'
            host: 'localhost:4080'
            connection: 'keep-alive'
          trailers: {}
          method: 'GET'
          url: '/test1?box=share-123'
          files: {}
          body: {}
        done()

  describe 'when recording a POST form-urlencoded request', ->
    reqUrl = null
    it 'should accept the request', (done) ->
      reqOptions =
        uri: "#{recorderBaseUrl}/test2"
        qs: {box: 'share-123'}
        method: 'POST'
        headers:
          'user-agent': 'Mocha Test Runner 1.0'
          'some-custom-header': 'nom noms'
        form:
          some: 'object'
          key: 'value'
      request reqOptions, (err, response, body) ->
        response = response.toJSON();
        reqUrl = response.request.uri.path
        expect(err).to.be null
        expect(response.statusCode).to.be 200

        done()

    it 'should store the request', (done) ->
      recorder.store.getUrl reqUrl, (err, recorded) ->
        expect(err).to.be null
        expect(recorded).to.be.an 'array'
        recorded = recorded.pop()
        expect(recorded).to.eql
          httpVersion: '1.1'
          headers:
            'user-agent': 'Mocha Test Runner 1.0'
            'some-custom-header': 'nom noms'
            host: 'localhost:4080'
            'content-type': 'application/x-www-form-urlencoded'
            'content-length': '21'
            connection: 'keep-alive'
          trailers: {}
          method: 'POST'
          url: '/test2?box=share-123'
          files: {}
          body:
            some: 'object'
            key: 'value'
        done()

  describe 'when recording a POST multipart request', ->
    reqUrl = null
    it 'should accept the request', (done) ->
      reqOptions =
        uri: "#{recorderBaseUrl}/test3"
        qs: {box: 'share-123'}
        method: 'POST'
        headers:
          'user-agent': 'Mocha Test Runner 1.0'
          'some-custom-header': 'nom noms'
        formData:
          some: 'object'
          key: 'value'
          some_file: fs.createReadStream __dirname + '/panda.jpg'
      request reqOptions, (err, response, body) ->
        throw err if err
        response = response.toJSON();
        reqUrl = response.request.uri.path
        expect(err).to.be null
        expect(response.statusCode).to.be 200

        done()

    it 'should store the request', (done) ->
      recorder.store.getUrl reqUrl, (err, recorded) ->
        expect(err).to.be null
        expect(recorded).to.be.an 'array'
        recorded = recorded.pop()
        expect(recorded.headers['content-type']).to.contain 'multipart/form-data'
        # delete the values we don't want to test for equality
        delete recorded.headers['content-type']
        delete recorded.files.some_file.name
        delete recorded.files.some_file.path
        expect(recorded).to.eql
          httpVersion: '1.1'
          headers:
            'user-agent': 'Mocha Test Runner 1.0'
            'some-custom-header': 'nom noms'
            host: 'localhost:4080'
            'content-length': '62931'
            connection: 'keep-alive'
          trailers: {}
          method: 'POST'
          url: '/test3?box=share-123'
          files:
            some_file:
              fieldname: 'some_file'
              originalname: 'panda.jpg'
              encoding: '7bit'
              mimetype: 'image/jpeg'
              extension: 'jpg'
              size: 62505
              truncated: false
              buffer: null
          body:
            some: 'object'
            key: 'value'
        done()

  describe 'when replaying the GET request', ->
    it 'should look like the original request', (done) ->
      # get a new recorder just to make sure there is no logic
      # that accidentally attaches to state to the particular instance
      # that would be necessary for replay
      replayer = new Recorder recorderOpts
      replayer.setBaseUrl(receiverBaseUrl + '/')
      expect(replayer.baseUrl).to.be receiverBaseUrl + '/'
      replayer.replay 'test1', done

  describe 'when replaying the POST form-urlencoded request', ->
    it 'should look like the original request', (done) ->
      replayer = new Recorder recorderOpts
      replayer.setBaseUrl(receiverBaseUrl + '/')
      expect(replayer.baseUrl).to.be receiverBaseUrl + '/'
      replayer.replay 'test2', done

  describe 'when replaying the POST multipart request', ->
    it 'should look like the original request', (done) ->
      replayer = new Recorder recorderOpts
      replayer.setBaseUrl(receiverBaseUrl + '/')
      expect(replayer.baseUrl).to.be receiverBaseUrl + '/'
      replayer.replay 'test3', (err, res, body) ->
        expect body
          .not.to.be null
        # our mock server returns request parameters as its
        # response so that we can verify they match the
        # original request
        body = JSON.parse body
        expect body.files.some_file
          .not.to.be null


        done err
