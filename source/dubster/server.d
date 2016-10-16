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
module dubster.server;

import dubster.job;
import dubster.dmd;
import dubster.dub;
import dubster.reporter;
import dubster.analyser;
import dubster.persistence;

import vibe.data.json;
import vibe.db.mongo.collection;
import vibe.core.task;
import vibe.http.server;
import vibe.db.mongo.database;
import vibe.web.common;
import vibe.http.websockets;
import vibe.http.router : URLRouter;
import vibe.web.rest;
import vibe.web.web : registerWebInterface;
import vibe.http.fileserver : serveStaticFiles, HTTPFileServerSettings, serveStaticFile;
import vibe.core.log : logInfo;
import vibe.core.core : setTimer, sleep;
import vibe.core.concurrency;
import vibe.textfilter.urlencode : urlEncode;
import std.stdio : writeln, writefln;
import std.algorithm : setDifference, setIntersection, sort, uniq, cmp, copy, each, map, filter, remove, countUntil, partition, count;
import std.range : chain;
import std.array : array, appender;
import std.traits : hasMember;
import core.time;
import std.typecons : tuple, Nullable;
import std.datetime : Clock, UTC, SysTime;

struct JobSetQueryParams
{
	@optional string query;
	@optional int skip;
	@optional int limit = 25;
	@optional JobTrigger[] types;
}
struct PackageQueryParams
{
	@optional string query;
	@optional int skip;
	@optional int limit = 24;
}
struct ReleaseQueryParams
{
	@optional string query;
	@optional int skip;
	@optional int limit = 24;	
}
struct JobResultsQueryParams
{
	@optional @name("package") string pkg;
	@optional @name("version") string ver;
	@optional JobTrigger[] types;
	@optional int skip;
	@optional int limit = 24;
}
struct JobSetComparison
{
	JobSet to;
	JobSet from;
	JobComparison[] items;
}
@path("/api/v1")
interface IDubsterApi
{
	@path("/worker/job")
	Json getJob();
	@path("/worker/results")
	void postJobResult(JobResult results);
	@path("/results")
	JobResult[] getJobResults(JobResultsQueryParams query);
	@path("/results/:id")
	JobResult getJobResult(string _id);
	@path("/pull/:component/:number")
	void postPullRequest(string _component, string _number);
	@path("/dmd")
	DmdVersion[] getDmds();
	@path("/jobsets")
	JobSet[] getJobSets(JobSetQueryParams query);
	@path("/jobsets/:id")
	JobSet getJobSet(string _id);
	@path("/jobsets/:id/jobs")
	JobResult[] getJobsInJobSet(string _id, int skip = 0, int limit = 24);
	@path("/jobsets/:from/compare/:to")
	JobSetComparison getComparison(string _from, string _to);
	@path("/packages")
	PackageStats[] getPackages(PackageQueryParams query);
	@path("/packages/:package")
	PackageStats getPackage(string _package);
	@path("/packages/:package/versions")
	PackageVersionStats[] getVersionedPackages(string _package, int skip = 0, int limit = 24);
	@path("/releases")
	DmdReleaseStats[] getReleases(ReleaseQueryParams query);
	@path("/releases/:release")
	DmdPackageStats[] getReleasePackages(ReleaseQueryParams query, string _release);
}
struct ServerSettings
{
	HTTPServerSettings httpSettings;
	bool doSync;
}
template hasBsonId(T)
{
	enum hasBsonId = true; // TODO: check if T has a member that is a BsonObjectID and is named _id or has an @name("_id") attribute
}
struct PackageVersionInfo
{
	string _id;
	string name;
	string ver;
	SysTime datetime;
}
struct PackageVersionStats
{
	PackageVersionInfo pkg;
	int success;
	int failed;
	int unknown;
	this(DubPackage s, int success, int failed, int unknown)
	{
		pkg = PackageVersionInfo(s._id,s.name,s.ver,s.datetime);
		this.success = success;
		this.failed = failed;
		this.unknown = unknown;
	}
}
struct PackageInfo
{
	string name;
	string description;
}
struct PackageStats
{
	PackageInfo pkg;
	int success;
	int failed;
	int unknown;
	this(DubPackage s, int success, int failed, int unknown)
	{
		pkg = PackageInfo(s.name,s.description);
		this.success = success;
		this.failed = failed;
		this.unknown = unknown;
	}
}
struct DmdReleaseStats
{
	DmdVersion dmd;
	int success;
	int failed;
	int unknown;
}
struct DmdPackageStats
{
	Job job;
	Timestamp start;
	Timestamp finish;
	ErrorStats error;
	this(JobResult result)
	{
		job = result.job;
		start = result.start;
		finish = result.finish;
		error = result.error;
	}
}
class BadgeService
{
	Persistence db;
	this(Persistence db)
	{
		this.db = db;
	}
	@path("/badge/:package/version/:version/:dmd")
	void getBadge(string _package, string _version, string _dmd, HTTPServerResponse res)
	{
		string id = _package ~ ":" ~ _version;
		auto stats = db.find!("dmdPackageStats",DmdPackageStats)(["job.pkg._id":id,"job.dmd.ver":_dmd]);
		if (stats.empty)
			throw new HTTPStatusException(404);
		auto result = stats.front();
		string text, color;
		if (result.error.isSuccess())
		{
			color = "green";
			text = "success";
		} else if (result.error.isFailed())
		{
			color = "red";
			text = "failed";
		} else
		{
			color = "lightgray";
			text = "n/a";
		}
		auto encode(string input)
		{
			import std.array : replace;
			return urlEncode(input).replace("-","--");
		}
		res.redirect("https://img.shields.io/badge/"~encode(_dmd)~"-"~encode(text)~"-"~encode(color)~".svg",301);
	}
}
class Server : IDubsterApi
{
	DmdVersion[] knownDmds;
	DubPackage[] knownPackages;
	JobScheduler scheduler;
	Persistence db;
	ServerSettings settings;
	this(ServerSettings s, Persistence db, IReporter reporter)
	{
		settings = s;
		this.db = db;
		scheduler = new JobScheduler();
		auto fileSettings = new HTTPFileServerSettings();
		fileSettings.maxAge = 31536000.seconds;
		auto fileSettingsIndex = new HTTPFileServerSettings();
		fileSettingsIndex.maxAge = 0.seconds;
		auto router = new URLRouter;
		auto badgeInterface = new BadgeService(db);
		router.registerRestInterface(this).registerWebInterface(badgeInterface);
		router.get("/events", handleWebSockets(&handleWebSocketConnection));
		router.get("/styles-*", serveStaticFiles("public/",fileSettings));
		router.get("/bundle.*", serveStaticFiles("public/",fileSettings));
		router.get("/*", serveStaticFile("public/index.html",fileSettingsIndex));
		listenHTTP(s.httpSettings, router);

		restore();
		if (s.doSync)
			sync();
	}
	void handleWebSocketConnection(scope WebSocket socket)
	{
		int counter = 0;
		logInfo("Got new web socket connection.");
		auto task = Task.getThis();
		db.subscribe(task);
		try
		{
			while (true) {
				receiveTimeout(1.seconds,
					(EventMessage message){
						socket.send(message.serializeToJson().toString());
					});
				if (!socket.connected) break;
			}
			logInfo("Client disconnected.");
		} catch (Exception e)
		{
			logInfo("Exception: %s",e.msg);
		}
		db.unsubscribe(task);
	}
	Json getJob()
	{
		auto js = scheduler.getHighPrioJobSet();
		if (js.isNull)
			return Json(null);

		auto job = scheduler.getJob(j=>(j.jobSet == js.id));
		if (job.isNull())
			return Json(null);

		Json j = job.get.serializeToJson();
		j["started"] = getTimestamp();
		db.append!("executingJobs")([j]);
		db.remove!("pendingJobs")(job.get);
		js.pendingJobs -= 1;
		js.executingJobs += 1;
		if (js.started == Timestamp.init)
		{
			js.started = getTimestamp();
			scheduler.updateJobSet(js);
			db.update!("jobSets")(["_id":Bson(js.id)],["$set":["pendingJobs":Bson(js.pendingJobs),"executingJobs":Bson(js.executingJobs),"started":Bson(js.started)]]);
		} else
		{
			scheduler.updateJobSet(js);
			db.update!("jobSets")(["_id":Bson(js.id)],["$set":["pendingJobs":Bson(js.pendingJobs),"executingJobs":Bson(js.executingJobs)]]);
		}
		return job.get().serializeToJson();
	}
	void postJobResult(JobResult results)
	{
		auto raw = results.getRawJobResult();
		db.append!("rawJobResults")([raw]);
		db.append!("results")([results]);
		db.remove!("executingJobs")(results.job);
		auto js = scheduler.getJobSet(results.job.jobSet);
		js.executingJobs -= 1;
		js.completedJobs += 1;
		if (results.error.isSuccess)
			js.success += 1;
		if (results.error.isFailed)
			js.failed += 1;
		if (results.error.isUndefined)
			js.unknown += 1;
		if (js.pendingJobs == 0)
		{
			js.finished = getTimestamp();
			scheduler.removeJobSet(js.id);
			db.update!("jobSets")(["_id":Bson(js.id)],["$set":["executingJobs":Bson(js.executingJobs),"completedJobs":Bson(js.completedJobs),"success":Bson(js.success),"failed":Bson(js.failed),"unknown":Bson(js.unknown),"finished":Bson(js.finished)]]);
		} else
		{
			scheduler.updateJobSet(js);
			db.update!("jobSets")(["_id":Bson(js.id)],["$set":["executingJobs":Bson(js.executingJobs),"completedJobs":Bson(js.completedJobs),"success":Bson(js.success),"failed":Bson(js.failed),"unknown":Bson(js.unknown)]]);
		}
		db.updateStats(results);
	}
	/*void postJob(JobRequest job)
	{
		auto js = JobSet(JobTrigger.Manual, "dmd: "~job.dmd~", pkg: "~job.pkg);
		// todo: see if jobset already exists, if it does, continue
		if (job.dmd == "*")
		{
			// run pkg against all dmds
			if (job.pkg == "*")
				throw new RestException(400, Json(["code":Json(1000),"msg":Json("Cannot wildcard both dmd and pkg")]));
			
			auto pkgs = knownPackages.filter!(p => p.name == job.pkg || p._id == job.pkg).array();
			if (pkgs.length == 0)
				throw new RestException(400, Json(["code":Json(1001),"msg":Json("Could not find any package for "~job.pkg)]));

			// todo: see if jobset already exists, if it does, continue
			auto jobs = createJobs(knownDmds,pkgs,js).array();
			if (jobs.length == 0)
				throw new RestException(400, Json(["code":Json(1002),"msg":Json("Skipped: resulted in zero jobs.")]));
			addJobs(jobs,js);
		} else
		{
			if (!job.dmd.isValidDiggerVersion())
				throw new RestException(400, Json(["code":Json(1003),"msg":Json("Invalid dmd version")]));
			auto dmd = DmdVersion(job.dmd);
			DubPackage[] pkgs;
			if (job.pkg == "*")
			{
				pkgs = knownPackages;
			} else
			{
				pkgs = knownPackages.filter!(p => p.name == job.pkg || p._id == job.pkg).array();
			}
			if (pkgs.length == 0)
				throw new RestException(400, Json(["code":Json(1001),"msg":Json("Could not find any package for "~job.pkg)]));
			// run dmd against all packages
			auto jobs = createJobs([dmd],pkgs,js).array();
			if (jobs.length == 0)
				throw new RestException(400, Json(["code":Json(1002),"msg":Json("Skipped: resulted in zero jobs.")]));
			addJobs(jobs,js);
		}
	}*/
	JobResult[] getJobResults(JobResultsQueryParams query)
	{
		Bson[string] constraints;
		if (query.pkg.length > 0)
			constraints["job.pkg.name"] = Bson(query.pkg);
		if (query.ver.length > 0)
			constraints["job.pkg.ver"] = Bson(query.ver);
		if (query.types.length > 0)
			constraints["trigger"] = Bson(["$in": Bson(query.types.map!(to!string).map!(a=>Bson(a)).array)]);
		if (constraints.length == 0)
			return db.find!("results",JobResult)(query.skip,query.limit).sort(["created":-1]).array();
		return db.find!("results",JobResult)(constraints,query.skip,query.limit).sort(["created":-1]).array();
	}
	JobResult getJobResult(string _id)
	{
		auto cursor = db.find!("results",JobResult)(["job._id": _id]);
		if (cursor.empty)
			throw new RestException(404, Json(["code":Json(1007),"msg":Json("Not Found.")]));
		return cursor.front();
	}
	void postPullRequest(string _component, string _number)
	{
		JobTrigger trigger;
		switch(_component)
		{
			case "dmd": trigger = JobTrigger.DmdPullRequest; break;
			case "druntime": trigger = JobTrigger.DruntimePullRequest; break;
			case "phobos": trigger = JobTrigger.PhobosPullRequest; break;
			default:
				throw new RestException(400, Json(["code":Json(1004),"msg":Json("Invalid component, must be one of [dmd,phobos,druntime].")]));
		}
		uint number;
		try {
			number = _number.to!uint;
		} catch (Exception e)
		{
			throw new RestException(400, Json(["code":Json(1005),"msg":Json("Last path segment must be a positive integer.")]));
		}
		processPullRequest(trigger,number);
	}
	DmdVersion[] getDmds()
	{
		return knownDmds;
	}
	JobSet[] getJobSets(JobSetQueryParams query)
	{
		Bson[string] constraints;
		if (query.query.length > 0)
			constraints["triggerId"] = Bson(["$regex": Bson(query.query)]);
		if (query.types.length > 0)
			constraints["trigger"] = Bson(["$in": Bson(query.types.map!(to!string).map!(a=>Bson(a)).array)]);
		if (constraints.length == 0)
			return db.find!("jobSets",JobSet)(query.skip,query.limit).sort(["created":-1]).array();
		return db.find!("jobSets",JobSet)(constraints,query.skip,query.limit).sort(["created":-1]).array();
	}
	JobSet getJobSet(string _id)
	{
		auto cursor = db.find!("jobSets",JobSet)(["_id": _id]);
		if (cursor.empty)
			throw new RestException(404, Json(["code":Json(1007),"msg":Json("Not Found.")]));
		return cursor.front();
	}
	JobResult[] getJobsInJobSet(string _id, int skip = 0, int limit = 24)
	{
		return db.find!("results",JobResult)(["job.jobSet":_id],skip,limit).sort(["start":-1]).array();
	}
	JobSetComparison getComparison(string _from, string _to)
	{
		auto readData(string id)
		{
			auto cursor = db.find!("results",JobResultSummary)(["job.jobSet": id]);
			auto app = appender!(JobResultSummary[]);
			cursor.copy(app);
			return app.data;
		}
		auto getJobSet(string id)
		{
			auto cursor = db.find!("jobSets",JobSet)(["_id":id]);
			if (cursor.empty)
				throw new RestException(404, Json(["code":Json(1007),"msg":Json("Not Found JobSet "~_to)]));
			return cursor.front();			
		}
		auto toJobSet = getJobSet(_to);
		auto fromJobSet = getJobSet(_from);

		auto toJobs = readData(_to);
		auto fromJobs = readData(_from);
		return JobSetComparison(toJobSet,fromJobSet,compareJobResultSets(fromJobs,toJobs));
	}
	PackageStats[] getPackages(PackageQueryParams query)
	{
		Bson[string] constraints;
		if (query.query.length > 0)
			constraints["$or"] = Bson([Bson(["pkg.name":Bson(["$regex":Bson(query.query)])]),Bson(["pkg.description":Bson(["$regex":Bson(query.query)])])]);
		if (constraints.length == 0)
			return db.find!("packageStats",PackageStats)(query.skip,query.limit).array();
		return db.find!("packageStats",PackageStats)(constraints,query.skip,query.limit).array();
	}
	PackageStats getPackage(string _package)
	{
		auto cursor = db.find!("packageStats",PackageStats)(["pkg.name":_package]);
		if (cursor.empty)
			throw new RestException(404, Json(["code":Json(1007),"msg":Json("Could not find package")]));
		return cursor.front();
	}
	PackageVersionStats[] getVersionedPackages(string _name, int skip = 0, int limit = 24)
	{
		return db.find!("packageVersionStats",PackageVersionStats)(["pkg.name":_name],skip,limit).array();
	}
	DmdReleaseStats[] getReleases(ReleaseQueryParams query)
	{
		Bson[string] constraints;
		if (query.query.length > 0)
			constraints["dmd.ver"] = ["$regex":Bson(query.query)];
		if (constraints.length == 0)
			return db.find!("dmdReleaseStats",DmdReleaseStats)(query.skip,query.limit).array();
		return db.find!("dmdReleaseStats",DmdReleaseStats)(constraints,query.skip,query.limit).array();
	}
	DmdPackageStats[] getReleasePackages(ReleaseQueryParams query, string _release)
	{
		Bson[string] constraints = ["job.dmd.ver":Bson(_release)];
		if (query.query.length > 0)
			constraints["job.pkg.name"] = ["$regex":Bson(query.query)];
		if (constraints.length == 0)
			return db.find!("dmdPackageStats",DmdPackageStats)(query.skip,query.limit).array();
		return db.find!("dmdPackageStats",DmdPackageStats)(constraints,query.skip,query.limit).array();
	}
	private void restore()
	{
		db.updateComputedData();
		auto previousJobs = db.readAll!("pendingJobs",Job).array();
		auto previousJobSets = db.readAll!("jobSets",JobSet).array();
		if (previousJobs.length > 0)
			logInfo("Got %s previous jobs",previousJobs.length);
		if (previousJobSets.length > 0)
			logInfo("Got %s previous job sets",previousJobSets.length);
		scheduler.restore(previousJobs,previousJobSets);
		knownDmds = db.readAll!("dmds",DmdVersion).array();
		knownDmds.sort();
		knownPackages = db.readAll!("packages",DubPackage).array();
		knownPackages.sort();
		db.ensureIndex!("packageStats")([tuple("pkg.name",1),tuple("pkg.description",1)]);
	}
	private void processDmdReleases(DmdVersions)(DmdVersions latest)
		if (is(ElementType!DmdVersions == DmdVersion))
	{
		auto newDmds = latest.setDifference(knownDmds).array();
		if (newDmds.length > 0)
			logInfo("Got %s new dmds", newDmds.length);
		auto sameDmds = latest.setIntersection(knownDmds).array();
		if (newDmds.length == 0 && sameDmds.length == knownDmds.length)
			return;

		foreach(dmd; newDmds)
		{
			auto js = JobSet(JobTrigger.DmdRelease, dmd.ver);
			if (db.exists!"jobSets"(["_id":js.id]))
				continue;
			auto jobs = createJobs([dmd],knownPackages,js).array();
			if (jobs.length == 0)
				continue;
			addJobs(jobs,js);
		}
		auto oldDmds = knownDmds.setDifference(latest).array();
		knownDmds = chain(newDmds,sameDmds).array;
		knownDmds.sort();
		if (oldDmds.length > 0)
			db.remove!"dmds"(oldDmds);
		if (newDmds.length > 0)
			db.append!"dmds"(newDmds);
	}
	private void processDubPackages(DubPackages)(DubPackages latest)
		if (is(ElementType!DubPackages == DubPackage))
	{
		auto newPackages = latest.setDifference(knownPackages).array();
		if (newPackages.length > 0)
			logInfo("Got %s new packages", newPackages.length);
		auto samePackages = latest.setIntersection(knownPackages).array();
		if (newPackages.length == 0 && samePackages.length == knownPackages.length)
			return;

		auto processedPackages = appender!(DubPackage[]);
		foreach(pkg; newPackages)
		{
			try
			{
				pkg.extendDubPackageWithInfo();
				auto js = JobSet(JobTrigger.PackageUpdate,pkg.name~":"~pkg.ver);
				if (db.exists!"jobSets"(["_id":js.id]))
					continue;
				auto jobs = createJobs(knownDmds,[pkg],js).array();
				if (jobs.length == 0){
					processedPackages.put(pkg);
					continue;
				}
				db.append!"packages"([pkg]);
				addJobs(jobs,js);
				processedPackages.put(pkg);
			} catch (Exception e)
			{
				logInfo("Exception while processing new package: %s",e);
			}
			sleep(50.msecs);
		}
		auto oldPackages = knownPackages.setDifference(latest).array();
		knownPackages = chain(processedPackages.data,samePackages).array();
		knownPackages.sort();
		if (oldPackages.length > 0)
			db.remove!"packages"(oldPackages);
	}
	private DmdVersion createDmdVersion(JobSet js)
	{
		string pull = js.getPullRequestRepo();
		string masterSha = getDmdMasterLatestSha();
		string ver = masterSha~" + "~pull~"#"~js.triggerId;
		assert(ver.isValidDiggerVersion());
		return DmdVersion(ver,Clock.currTime(UTC()).toISOExtString());
	}
	private void processPullRequest(JobTrigger trigger, uint seq)
	{
		assert(trigger == JobTrigger.DmdPullRequest || trigger == JobTrigger.DruntimePullRequest || trigger == JobTrigger.PhobosPullRequest);
		auto js = JobSet(trigger, seq.to!string);
		if (!js.doesPullRequestsExists)
			throw new RestException(404, Json(["code":Json(1009),"msg":Json("Cannot find that pull request")]));
		if (db.exists!"jobSets"(["_id":js.id]))
			throw new RestException(409, Json(["code":Json(1008),"msg":Json("JobSet already exists")]));
		logInfo("Got %s",js);
		auto dmd = createDmdVersion(js);
		auto jobs = createJobs([dmd],knownPackages,js).array();
		if (jobs.length == 0)
			return;
		addJobs(jobs,js);
	}
	private void addJobs(Job[] jobs, JobSet js)
	{
		auto findRawJobResult(Job job){
			auto cursor = db.find!("rawJobResults",RawJobResult)(["_id":job.id]);
			if (cursor.empty)
				return Nullable!(RawJobResult)();
			return Nullable!(RawJobResult)(cursor.front);
		}
		auto jobsWithResults = jobs
			.map!(job=>tuple!("job","result")(job,findRawJobResult(job)))
			.array();
		auto cachedJobs = jobsWithResults.partition!(t=>t.result.isNull);
		auto newJobs = jobsWithResults[0..$-cachedJobs.length].map!(t=>t.job).array();

		auto results = cachedJobs.map!((t){
			t.job.created = t.result.created;
			return JobResult(t.job,t.result.start,t.result.finish,t.result.output,t.result.output.parseError);
		}).array();

		db.append!("results")(results);
		js.success = cast(int)results.count!(r=>r.error.isSuccess);
		js.failed = cast(int)results.count!(r=>r.error.isFailed);
		js.unknown = cast(int)results.count!(r=>r.error.isUndefined);
		js.completedJobs = results.length;
		js.pendingJobs = newJobs.length;
		db.append!"pendingJobs"(newJobs);
		db.append!"jobSets"([js]);
		foreach(result; results)
			db.updateStats(result);
		scheduler.addJobs(newJobs,js);
		logInfo("Created %s new jobs triggered by %s, (%s were cached)",jobs.length,js,results.length);
	}
	private void sync()
	{
		try
		{
			auto latestDmds = fetchDmdVersions.array.sort().array();
			auto latestPackages = fetchDubPackages.sort();

			processDubPackages(latestPackages);
			processDmdReleases(latestDmds);
		} catch (Exception e)
		{
			logInfo("Error in sync(): %s",e.msg);
		}
		setTimer(5.minutes, &this.sync, false);
	}
}
void updateStats(Persistence db, JobResult results)
{
	db.updatePackageStats(results);
	db.updateDmdReleaseStats(results);
	db.updateDmdPackageStats(results);
}
void updatePackageStats(Persistence db, JobResult results)
{
	void update(string collection, S)(JobResult result, string id, string indexField)
	{
		auto stats = db.find!(collection,S)([indexField:id]).limit(1);
		if (stats.empty)
		{
			auto stat = S(results.job.pkg,results.error.isSuccess,results.error.isFailed,results.error.isUndefined);
			db.append!(collection)(stat);
		} else if (results.error.isSuccess)
			db.update!(collection)([indexField:id],["$set":["success":(stats.front().success + 1)]]);
		else if (results.error.isFailed)
			db.update!(collection)([indexField:id],["$set":["failed":(stats.front().failed + 1)]]);
		else
			db.update!(collection)([indexField:id],["$set":["unknown":(stats.front().unknown + 1)]]);
	}
	if (!(results.job.trigger == JobTrigger.DmdRelease || results.job.trigger == JobTrigger.PackageUpdate))
		return;
	update!("packageStats",PackageStats)(results, results.job.pkg.name, "pkg.name");
	update!("packageVersionStats",PackageVersionStats)(results, results.job.pkg._id, "pkg._id");
}
void updateDmdReleaseStats(Persistence db, JobResult results)
{
	void update(string collection, S)(JobResult result, string id)
	{
		auto stats = db.find!(collection,S)(["dmd._id":id]).limit(1);
		if (stats.empty)
		{
			auto stat = S(result.job.dmd,results.error.isSuccess,results.error.isFailed,results.error.isUndefined);
			db.append!(collection)(stat);
		} else if (results.error.isSuccess)
			db.update!(collection)(["dmd._id":id],["$set":["success":(stats.front().success + 1)]]);
		else if (results.error.isFailed)
			db.update!(collection)(["dmd._id":id],["$set":["failed":(stats.front().failed + 1)]]);
		else
			db.update!(collection)(["dmd._id":id],["$set":["unknown":(stats.front().unknown + 1)]]);
	}
	if (!(results.job.trigger == JobTrigger.DmdRelease || results.job.trigger == JobTrigger.PackageUpdate))
		return;
	update!("dmdReleaseStats",DmdReleaseStats)(results, results.job.dmd.id);
}
void updateDmdPackageStats(Persistence db, JobResult result)
{
	if (!(result.job.trigger == JobTrigger.DmdRelease || result.job.trigger == JobTrigger.PackageUpdate))
		return;
	db.append!("dmdPackageStats")(DmdPackageStats(result));
}
void updateComputedData(Persistence db)
{
	logInfo("Updating Computed Data");
	int skip = 0;
	db.drop!("packageStats");
	db.drop!("packageVersionStats");
	db.drop!("dmdReleaseStats");
	db.drop!("dmdPackageStats");
	do
	{
		auto cursor = db.find!("results",JobResult)(skip,24).array();
		foreach(r; cursor)
			db.updateStats(r);
		if (cursor.length != 24)
			break;
		skip += 24;
	} while (1);
	logInfo("Computed Data Updated");
}
