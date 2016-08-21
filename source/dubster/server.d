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
import std.algorithm : setDifference, setIntersection, sort, uniq;
import std.range : chain;
import std.array : array;
import std.traits : hasMember;

struct JobRequest
{
	string dmd;
	string pkg;
}
interface IDubsterApi
{
	@path("/job")
	Json getJob();
	@path("/job")
	void postJob(JobRequest job);
	@path("/results")
	void postJobResult(JobResult results);
	@path("/pull/:component/:number")
	void postPullRequest(string _component, string _number);
	@path("/dmd")
	DmdVersion[] getDmds();
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
struct PersistenceMessage
{
	string collection;
	string type;
	Json data;
}
class PersistenceDispatcher
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
	private void dispatch(PersistenceMessage msg)
	{
		Task[] failedSends;
		foreach (s; subscribers)
			try s.send(msg); catch(Exception e) { failedSends ~= s; }
		foreach (t; failedSends)
			unsubscribe(t);
	}
	private void dispatch(string name, T)(string type, T t)
	{
		dispatch(PersistenceMessage(name,type,t.serializeToJson()));
	}
}
class Persistence : PersistenceDispatcher
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
	void replace(string name, T)(T t)
	{
		static assert(hasBsonId!T);
		auto collection = getCollection!name;
		try collection.drop(); catch(Exception e) {}
		collection.insert(t);
		dispatch!(name)("replace",t);
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
		router.get("/events", handleWebSockets(&handleWebSocketConnection));
		router.get("/public/*", serveStaticFiles("."));
		router.registerRestInterface(this);
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
					(PersistenceMessage message){
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
		if (js.pendingJobs == 0)
		{
			js.finished = getTimestamp();
			scheduler.removeJobSet(js.id);
			db.update!("jobSets")(["_id":Bson(js.id)],["$set":["executingJobs":Bson(js.executingJobs),"completedJobs":Bson(js.completedJobs),"finished":Bson(js.finished)]]);
		} else
		{
			scheduler.updateJobSet(js);
			db.update!("jobSets")(["_id":Bson(js.id)],["$set":["executingJobs":Bson(js.executingJobs),"completedJobs":Bson(js.completedJobs)]]);
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

		foreach(dmd; newDmds)
		{
			auto js = JobSet(JobTrigger.DmdRelease, dmd.ver);
			// todo: see if jobset already exists, if it does, continue
			auto jobs = createJobs([dmd],knownPackages,js).array();
			if (jobs.length == 0)
				continue;
			addJobs(jobs,js);
		}
		knownDmds = chain(newDmds,sameDmds).array.sort().array();
		db.replace!"dmds"(knownDmds);
	}
	private void processDubPackages(DubPackages)(DubPackages latest)
		if (is(ElementType!DubPackages == DubPackage))
	{
		auto newPackages = latest.setDifference(knownPackages).array();
		if (newPackages.length > 0)
			writefln("Got %s new packages", newPackages.length);
		auto samePackages = latest.setIntersection(knownPackages).array();

		foreach(pkg; newPackages)
		{
			auto js = JobSet(JobTrigger.PackageUpdate,pkg.name~":"~pkg.ver);
			// todo: see if jobset already exists, if it does, continue
			auto jobs = createJobs(knownDmds,[pkg],js).array();
			if (jobs.length == 0)
				continue;
			addJobs(jobs,js);
		}
		knownPackages = chain(newPackages,samePackages).array.sort().array();
		db.replace!"packages"(knownPackages);
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
		string ver = "master + "~pull~"#"~js.triggerId;
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