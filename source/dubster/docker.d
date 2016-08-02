/**
 * Dubster. Runs unittests on dub packages against latest dmd compiler's
 * Copyright (C) 2016  Sebastiaan Koppe
 * 
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 * 
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 * 
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */
module dubster.docker;

import vibe.d;
import vibe.stream.wrapper;
import std.bitmanip : bigEndianToNative;
import std.stdio;
import std.process;
import std.regex;
import std.conv : to;

         //"CpuPercent": 80,  @1.24
         //"MaximumIOps": 0,  @1.24
         //"MaximumIOBps": 0, @1.24
         //"OomScoreAdj": 500,  @1.24
         //"StorageOpt": {},  @1.24
         //"LinkLocalIPs":["169.254.34.68", "fe80::3468"] @1.24
struct DockerHost
{
  string protocol;
  string host;
  ushort port;
  string toString()
  {
    if (port != ushort.init)
      return protocol ~ "://" ~ host ~ ":" ~ port.to!string;
    return protocol ~ "://" ~ host;
  }
}
struct DockerRemote
{
  private {
    struct Empty {};
    DockerHost host;
    bool socket, tls;
    string certFile, caFile, keyFile;
    void parseHost(string hostString, bool tls)
    {
      auto reg = ctRegex!`^([a-z]+):\/\/([^:]+)(?::([0-9]+))?$`;
      auto matches = hostString.matchFirst(reg);
      if (!matches)
        throw new Exception("Failed to parse host string "~hostString);
      import std.stdio;
      switch (matches[1])
      {
        case "unix": assert(0,"unix socket is not supported");
        case "http": 
        case "https":
        case "tcp":
          string protocol = "http";
          if (tls)
            protocol = "https";
          ushort port = 2376;
          if (matches.length == 3 && !tls)
            port = 2375;
          else if (matches.length == 4)
            port = matches[3].to!ushort;
          host = DockerHost(protocol,matches[2],port);
          break;
        default: assert(0,"Unsupported protocol");
      }
    }
  }
  this(string host, string certPath, bool tls)
  {
    HTTPClient.setTLSSetupCallback(&setupTls);
    parseHost(host, tls);
    this.certFile = certPath~"/cert.pem";
    this.caFile = certPath~"/ca.pem";
    this.keyFile = certPath~"/key.pem";
  }
  this(string host)
  {
    parseHost(host, false);
  }
  void request(T = Empty)(HTTPMethod method, string path, scope void delegate(scope HTTPClientResponse) responder, T t = T.init)
  {
    requestHTTP(host.toString~"/"~path,
      (scope req){
        req.method = method;
        static if (!is(T : Empty))
        {
          req.headers.addField("Content-Type","application/json");
          req.writeJsonBody(t);
        }
      },
      responder
    );
  }
  void opDispatch(string s, T)(string path, T t, scope void delegate(scope HTTPClientResponse) responder)
  {
    static if (s == "post")
      request(HTTPMethod.POST,path,responder,t);
    else static if (s == "put")
      request(HTTPMethod.PUT,path,responder,t);
  }
  void opDispatch(string s)(string path, scope void delegate(scope HTTPClientResponse) responder)
  {
    static if (s == "get")
      request(HTTPMethod.GET,path,responder);
    else static if (s == "post")
      request(HTTPMethod.POST,path,responder);
    else static if (s == "drop")
      request(HTTPMethod.DELETE,path,responder);
    else static if (s == "put")
      request(HTTPMethod.PUT,path,responder);
  }
}
import std.utf : decodeFront;
import std.algorithm : min, find, countUntil, filter;
class DockerClient
{
  private DockerRemote remote;
  this(DockerRemote remote)
  {
    this.remote = remote;
  }
  this()
  {
    this(autodetectDockerRemote());
  }
  void streamLog(Sink)(ContainerId id, ref Sink sink)
  {
    remote.get("containers/"~id~"/logs?stdout=1&stderr=1&follow=1",(scope HTTPClientResponse res){
      if (res.statusCode >= 200 && res.statusCode < 300)
        res.readRawBody((scope reader){
          auto input = DockerStream(new ChunkedInputStream(reader));
          while (!input.empty)
            sink.put(input.decodeFront);
        });
      res.dropBody();
    }); 
  }
  ContainerId createContainer(CreateContainerRequest definition)
  {
    ContainerId id;
    remote.post("containers/create",definition,(scope HTTPClientResponse res){
      if (res.statusCode != 201)
        throw new Exception(res.bodyReader.readAllUTF8);
      auto r = res.readJson.deserializeJson!(CreateContainerResult);
      id = r.id;
    });
    return id;
  }
  Json inspectContainer(ContainerId id)
  {
    Json content;
    remote.get("containers/"~id~"/json",(scope HTTPClientResponse res){
      if (res.statusCode != 200)
        throw new Exception(res.bodyReader.readAllUTF8);
      content = res.readJson();
    });
    return content;
  }
  void startContainer(ContainerId id)
  {
    remote.post("containers/"~id~"/start",(scope HTTPClientResponse res){
      if (res.statusCode != 204)
        throw new Exception(res.bodyReader.readAllUTF8);
    });
  }
  void removeContainer(ContainerId id)
  {
    remote.drop("containers/"~id,(scope HTTPClientResponse res){
      if (res.statusCode != 204)
        throw new Exception(res.bodyReader.readAllUTF8);
    });
  }
  InspectState oneOffContainer(Sink)(CreateContainerRequest definition, ref Sink sink)
  {
    auto c = createContainer(definition);
    scope(exit) removeContainer(c);
    startContainer(c);
    streamLog(c,sink);
    auto content = inspectContainer(c);
    return content["State"].deserializeJson!InspectState;
  }
}
auto autodetectDockerRemote()
{
  auto host = environment.get("DOCKER_HOST");
  if (host is null)
  {
    version(Windows)
    {
      host = "http://127.0.0.1:2376"; // NOTE normally 2376 is for TLS, but where do we get the certs from??
    }
    version(Posix)
    {
      host = "unix:///var/run/docker.sock";
    }
  }
  auto certPath = environment.get("DOCKER_CERT_PATH");
  auto tlsVerify = environment.get("DOCKER_TLS_VERIFY");
  if (tlsVerify !is null)
  {
    assert(certPath !is null);
    auto verifyTls = tlsVerify is null ? false : tlsVerify == "1";
    return DockerRemote(host,certPath,verifyTls);
  }
  return DockerRemote(host);
}
alias ContainerId = string;
struct CreateContainerResult
{
  @name("Id") ContainerId id;
  @name("Warnings") Json warnings;
}
struct CreateContainerRequest
{
  @name("Hostname") string hostname = "hostname";
  @name("Domainname") string domainname = "";
  @name("User") string user = "";
  @name("AttachStdin")  bool attachStdin = false;
  @name("AttachStdout") bool attachStdout = true;
  @name("AttachStderr") bool attachStderr = true;
  @name("Tty") bool tty = false;
  @name("OpenStdin") bool openStdin = true;
  @name("StdinOnce") bool stdinOnce = false;
  @name("Env") string[] env;
  @name("Cmd") string[] cmd;
  @name("Entrypoint") string[] entrypoint;
  @name("Image") string image;
  @name("Labels") string[string] labels;
  @name("Volumes") string[string] volumes;
  @name("WorkingDir") string workingDir;
  @name("NetworkDisabled") bool networkDisabled = false;
  @name("MacAddress") string macAddress = "12:34:56:78:9a:bc";
  @name("ExposedPorts") string[string] exposedPorts;
  @name("StopSignal") string stopSignal = "SIGTERM";
  @name("HostConfig") HostConfig hostConfig;
}
struct HostConfig
{
  @name("Binds") string[] binds;
  @name("Links") string[] links;
  @name("Memory") int memory = 0;
  @name("MemorySwap") int memorySwap = 0;
  @name("MemoryReservation") int memoryReservation = 0;
  @name("KernelMemory") int kernelMemory = 0;
  @name("CpuShares") int cpuShares = 0;
  @name("CpuPeriod") int cpuPeriod = 0;
  @name("CpuQuota") int cpuQuota = 0;
  @name("CpusetCpus") string cpusetCpus = "";
  @name("CpusetMems") string cpusetMems = "";
  @name("BlkioWeight") int blkioWeight = 0;
  @name("BlkioWeightDevice") Json blkioWeightDevice = Json(null);
  @name("BlkioDeviceReadBps") Json blkioDeviceReadBps = Json(null);
  @name("BlkioDeviceReadIOps") Json blkioDeviceReadIOps = Json(null);
  @name("BlkioDeviceWriteBps") Json blkioDeviceWriteBps = Json(null);
  @name("BlkioDeviceWriteIOps") Json blkioDeviceWriteIOps = Json(null);
  @name("MemorySwappiness") int memorySwappiness = 0;
  @name("OomKillDisable") bool oomKillDisable = false;
  @name("PidMode") string pidMode = "";
  @name("PidsLimit") int pidsLimit = 0;
  @name("PortBindings") string[string] portBindings;
  @name("PublishAllPorts") bool publishAllPorts = false;
  @name("Privileged") bool privileged = false;
  @name("ReadonlyRootfs") bool readonlyRootfs = false;
  @name("Dns") string[] dns = ["8.8.8.8"];
  @name("DnsOptions") string[] dnsOptions;
  @name("DnsSearch") string[] dnsSearch;
  @name("ExtraHosts") Json extraHosts = Json(null);
  @name("VolumesFrom") string[] volumesFrom;
  @name("CapAdd") Json capAdd = Json(null);
  @name("CapDrop") Json capDrop = Json(null);
  @name("GroupAdd") Json groupAdd = Json(null);
  @name("RestartPolicy") RestartPolicy restartPolicy;
  @name("NetworkMode") string networkMode = "bridge";
  @name("Devices") string[] devices;
  @name("Ulimits") Json ulimits = Json(null);
  @name("LogConfig") LogConfig logConfig;
  @name("SecurityOpt") Json securityOpt = Json(null);
  @name("CgroupParent") string cgroupParent = "";
  @name("VolumeDriver") string volumeDriver = "";
  @name("ShmSize") int shmSize = 67108864;
}
struct RestartPolicy
{
  @name("Name") string nameb = "no";
  @name("MaximumRetryCount") int maximumRetryCount = 0;
}
struct LogConfig
{
  @name("Type") string type = "json-file";
  @name("Config") string[string] config;
}
struct InspectState
{
  @name("Paused") bool paused;
  @name("Status") string status;
  @name("Running") bool running;
  @name("FinishedAt") string finishedAt;
  @name("Error") string error;
  @name("StartedAt") string startedAt;
  @name("Pid") int pid;
  @name("ExitCode") int exitCode;
  @name("OOMKilled") bool oOMKilled;
  @name("Dead") bool dead;
  @name("Restarting") bool restarting;
}
void setupTls(TLSContext tls)
{
  tls.peerValidationCallback = delegate(scope TLSPeerValidationData data){
    return true;
  };
  tls.peerValidationMode = TLSPeerValidationMode.validCert;
  tls.useCertificateChainFile("/Users/skoppe/.docker/machine/certs/cert.pem");
  tls.useTrustedCertificateFile("/Users/skoppe/.docker/machine/certs/ca.pem");
  tls.usePrivateKeyFile("/Users/skoppe/.docker/machine/certs/key.pem");
}
// Docker multiplexes stdout/stderr over http with chunked transfer-encoding.
// The protocol is a 8 byte Header + Frame. The last four bytes in the Header
// is an uint32 representing the frame size.
// The first byte is either 1 -> stdout or 2 -> stderr, which designates the 
// type of the stream in the following frame.
struct DockerStream
{
  private {
    enum State {
      None,
      Header,
      StdoutFrame,
      StdinFrame
    };
    State state = State.None;
    uint frameBytesLeftToRead = 0;
    InputStream input;
    ubyte[128] buffer;
    ubyte[] data;
    bool done = false;
    void readHeader() {
      input.read(buffer[0..8]);
      frameBytesLeftToRead = buffer[4..8].bigEndianToNative!(uint)();
      state = buffer[0] == '\x01' ? State.StdoutFrame : State.StdinFrame;
    }
    void readData() {
      if (state == State.Header || state == State.None)
        readHeader();
      auto len = min(input.leastSize,buffer.length,frameBytesLeftToRead);
      frameBytesLeftToRead -= len;
      if (frameBytesLeftToRead == 0)
        state = State.Header;
      data = buffer[0..len];
      input.read(data);
    }
  }
  this(ChunkedInputStream input)
  {
    this.input = input;
  }
  @property bool empty()
  {
    if (state == State.None)
      readData();
    if (data.length > 0 || frameBytesLeftToRead > 0)
      return false;
    return input.empty;
  }
  void popFront()
  {
    if (data.length == 0)
      readData();
    data = data[1..$];
  }
  char front()
  {
    if (data.length == 0)
      readData();
    return char(data[0]);
  }
  bool isStdin()
  {
    return state == State.StdinFrame;
  }
  bool isStdout()
  {
    return state == State.StdoutFrame;
  }
}
