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

import vibe.d;
import dubster.job;
import dubster.dmd;
import dubster.dub;
import dubster.reporter;
import dubster.analyser;

import std.stdio : writeln, writefln;
import std.algorithm : setDifference, setIntersection, sort, uniq, cmp, copy;
import std.range : chain;
import std.array : array;
import std.traits : hasMember;

struct JobRequest
{
	string dmd;
	string pkg;
}
struct JobSetQueryParams
{
	@optional string query;
	@optional int skip;
	@optional int limit = 25;
	@optional JobTrigger[] types;
}
struct JobSetComparison
{
	JobComparison[] items;
}
@path("/api/v1")
interface IDubsterApi
{
	@path("/worker/job")
	Json getJob();
	@path("/worker/job")
	void postJob(JobRequest job);
	@path("/results")
	void postJobResult(JobResult results);
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
struct EventMessage
{
	string collection;
	string type;
	Json data;
}
class EventDispatcher
{
	private Task[] subscribers;
	void subscribe(Task t)
	{
		subscribers ~= t;
	}
	void unsubscribe(Task t)
	{
		auto idx = subscribers.countUntil!(i=>i==t);
		if (idx == -1)
			return;
		subscribers.remove(idx);
		subscribers = subscribers[0..$-1];
	}
	private void dispatch(EventMessage msg)
	{
		Task[] failedSends;
		foreach (s; subscribers)
			try s.send(msg); catch(Exception e) { failedSends ~= s; }
		foreach (t; failedSends)
			unsubscribe(t);
	}
	private void dispatch(string name, T)(string type, T t)
	{
		dispatch(EventMessage(name,type,t.serializeToJson()));
	}
}
class Persistence : EventDispatcher
{
	private MongoCollection pendingJobs, executingJobs, dmds, packages, results, jobSets;
	this(MongoDatabase db)
	{
		pendingJobs = db["pendingJobs"];
		executingJobs = db["executingJobs"];
		dmds = db["dmds"];
		packages = db["packages"];
		results = db["results"];
		jobSets = db["jobSets"];
	}
	private auto getCollection(string name)()
	{
		static assert(
			hasMember!(Persistence,name) &&
			is(typeof(__traits(getMember, this, name)) : MongoCollection),
			"collection "~name~" doesn't exist");
		return __traits(getMember, this, name);
	}
	void append(string name, T)(T t)
	{
		static assert(hasBsonId!T);
		getCollection!(name).insert(t);
		dispatch!(name)("append",t);
	}
	auto readAll(string name, T)()
	{
		static assert(hasBsonId!T);
		return getCollection!(name).find!T();
	}
	void remove(string name, T)(T t)
	{
		static assert(hasBsonId!T);
		getCollection!(name).remove(t);
		dispatch!(name)("remove",t);
	}
	void update(string name, Selector, Updates)(Selector s, Updates u)
	{
		getCollection!(name).update(s,u);
		struct Update
		{
			Selector selector;
			Updates updates;
		}
		dispatch!(name)("update",Update(s,u));
	}
	auto find(string name, T, Query)(Query q, int skip = 0, int limit = 0)
	{
		return getCollection!(name).find!(T,Query)(q,null,QueryFlags.None).skip(skip).limit(limit);
	}
	auto find(string name, T)(int skip = 0, int limit = 0)
	{
		auto cursor = getCollection!(name).find!(T).skip(skip);
		if (limit == 0)
			return cursor;
		return cursor.limit(limit);
	}
	bool exists(string name, Query)(Query q)
	{
		return !getCollection!(name).find(q).empty();
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
		scheduler = new JobScheduler();
		this.db = db;

		auto router = new URLRouter;
		router.registerRestInterface(this);
		router.get("/events", handleWebSockets(&handleWebSocketConnection));
		router.get("/*", serveStaticFiles("public/"));
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
	}
	void postJob(JobRequest job)
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
		return db.find!("jobSets",JobSet)(query.skip,query.limit).sort(["created":-1]).array();
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
	JobSetComparison getComparison(string _to, string _from)
	{
		auto readData(string id)
		{
			auto cursor = db.find!("results",JobResultSummary)(["job.jobSet": id]);
			auto app = appender!(JobResultSummary[]);
			cursor.copy(app);
			return app.data;
		}
		auto toSet = readData(_to);
		auto fromSet = readData(_from);
		return JobSetComparison(compareJobResultSets(toSet,fromSet));
	}
	private void restore()
	{
		auto previousJobs = db.readAll!("pendingJobs",Job).array();
		auto previousJobSets = db.readAll!("jobSets",JobSet).array();
		if (previousJobs.length > 0)
			writefln("Got %s previous jobs",previousJobs.length);
		if (previousJobSets.length > 0)
			writefln("Got %s previous job sets",previousJobSets.length);
		scheduler.restore(previousJobs,previousJobSets);
		knownDmds = db.readAll!("dmds",DmdVersion).array();
		knownPackages = db.readAll!("packages",DubPackage).array();
	}
	private void processDmdReleases(DmdVersions)(DmdVersions latest)
		if (is(ElementType!DmdVersions == DmdVersion))
	{
		auto newDmds = latest.setDifference(knownDmds).array();
		if (newDmds.length > 0)
			writefln("Got %s new dmds", newDmds.length);
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
			writefln("Got %s new packages", newPackages.length);
		auto samePackages = latest.setIntersection(knownPackages).array();
		if (newPackages.length == 0 && samePackages.length == knownPackages.length)
			return;

		foreach(pkg; newPackages)
		{
			auto js = JobSet(JobTrigger.PackageUpdate,pkg.name~":"~pkg.ver);
			if (db.exists!"jobSets"(["_id":js.id]))
				continue;
			auto jobs = createJobs(knownDmds,[pkg],js).array();
			if (jobs.length == 0)
				continue;
			addJobs(jobs,js);
		}
		auto oldPackages = knownPackages.setDifference(latest).array();
		knownPackages = chain(newPackages,samePackages).array();
		knownPackages.sort();
		if (oldPackages.length > 0)
			db.remove!"packages"(oldPackages);
		if (newPackages.length > 0)
			db.append!"packages"(newPackages);
	}
	private DmdVersion createDmdVersion(JobSet js)
	{
		string pull;
		final switch(js.trigger)
		{
			case JobTrigger.DmdRelease:
			case JobTrigger.PackageUpdate:
			case JobTrigger.Manual:
			case JobTrigger.Nightly:
				assert(false,"Can only create dmd version for pull requests");
			case JobTrigger.DmdPullRequest: pull = "dmd"; break;
			case JobTrigger.DruntimePullRequest: pull = "druntime"; break;
			case JobTrigger.PhobosPullRequest: pull = "phobos"; break;
		}
		string masterSha = getDmdMasterLatestSha();
		string ver = masterSha~" + "~pull~"#"~js.triggerId;
		assert(ver.isValidDiggerVersion());
		return DmdVersion(ver);
	}
	private void processPullRequest(JobTrigger trigger, uint seq)
	{
		assert(trigger == JobTrigger.DmdPullRequest || trigger == JobTrigger.DruntimePullRequest || trigger == JobTrigger.PhobosPullRequest);
		auto js = JobSet(trigger, seq.to!string);
		writefln("Got %s",js);
		auto dmd = createDmdVersion(js);
		auto jobs = createJobs([dmd],knownPackages,js).array();
		if (jobs.length == 0)
			return;
		addJobs(jobs,js);
	}
	private void addJobs(Job[] jobs, JobSet js)
	{
		js.pendingJobs = jobs.length;
		db.append!"pendingJobs"(jobs);
		db.append!"jobSets"([js]);
		scheduler.addJobs(jobs,js);
		writefln("Created %s new jobs triggered by %s",jobs.length,js);
	}
	private void sync()
	{
		try
		{
			auto latestDmds = getDmdTags.toReleases.importantOnly.array.sort().array();
			auto latestPackages = parseCodeDlangOrg.sort();

			processDubPackages(latestPackages);
			processDmdReleases(latestDmds);
		} catch (Exception e)
		{
			writefln("Error in sync(): %s",e.msg);
		}
		setTimer(5.minutes, &this.sync, false);
	}
}