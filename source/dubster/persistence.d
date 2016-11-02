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
module dubster.persistence;

import dubster.job;
import dubster.reporter;
import dubster.analyser;

import vibe.data.json;
import vibe.db.mongo.collection;
import vibe.core.task;
import vibe.db.mongo.database;
import vibe.core.concurrency;
import vibe.core.log : logInfo;

import std.traits : hasMember, hasUDA, isArray;
import std.algorithm : filter, remove, countUntil, map;
import std.array : array;
import std.format : format;

struct EventMessage
{
	string collection;
	string type;
	Json data;
}

class EventDispatcher
{
	private Task[] subscribers;
	void subscribe(Task t) {
		subscribers ~= t;
	}
	void unsubscribe(Task t) {
		auto idx = subscribers.countUntil!(i=>i==t);
		if (idx == -1)
			return;
		subscribers.remove(idx);
		subscribers = subscribers[0..$-1];
	}
	private void dispatch(EventMessage msg) {
		Task[] failedSends;
		foreach (s; subscribers)
			try s.send(msg); catch(Exception e) { failedSends ~= s; }
		foreach (t; failedSends)
			unsubscribe(t);
	}
	private void dispatch(string name)(string type) {
		if (name != "rawJobResults" && name != "system")
			dispatch(EventMessage(name,type,Json()));
	}
	private void dispatch(string name, T)(string type, T t) {
		if (name != "rawJobResults" && name != "system")
			dispatch(EventMessage(name,type,t.serializeToJson()));
	}
}

struct Version
{
	int ver;
}

struct Config
{
	private {
		Persistence db;
		Version ver;
	}
	this(Persistence db) {
		auto col = db.find!("system",Version)(["id":"version"]);
		if (col.empty)
    {
      import std.meta;
      template isMigrator(alias T) {
        enum isMigrator = hasUDA!(mixin(T),Version);
      }
      enum migrators = staticSort!(sortMigrators,Filter!(isMigrator,__traits(allMembers, dubster.persistence)));
      enum lastVersion = getMigratorVersion!(migrators[$-1]);
      if (db.emptyOld!("results"))
        ver = Version(lastVersion);
      else
        ver = Version(0);
			struct IndexedVersion
			{
				string id;
				int ver;
			}
			db.append!("system")(IndexedVersion("version",0));
		}
		else
			ver = col.front();
	}
	auto getVersion() {
		return ver;
	}
	auto updateVersion(int newVersion){
		db.update!("system")(["id":"version"],["$set":["ver":Bson(newVersion)]]);
		ver.ver = newVersion;
	}
}

class Persistence : EventDispatcher
{
	private {
		MongoCollection jobs, dmds, packages, 
			jobSets, packageStats, packageVersionStats, dmdReleaseStats, 
			rawJobResults, system;
		Config _config;
    MongoDatabase db;
	}

	this(MongoDatabase db) {
		jobs = db["jobs"];
		dmds = db["dmds"];
		packages = db["packages"];
		jobSets = db["jobSets"];
		packageStats = db["packageStats"];
		packageVersionStats = db["packageVersionStats"];
		dmdReleaseStats = db["dmdReleaseStats"];
		rawJobResults = db["rawJobResults"];
		system = db["system"];
		_config = Config(this);
    this.db = db;
	}
	private auto getCollection(string name)() {
		static assert(
			hasMember!(Persistence,name) &&
			is(typeof(__traits(getMember, this, name)) : MongoCollection),
			"collection "~name~" doesn't exist");
		return __traits(getMember, this, name);
	}
	@property auto config() { return _config; }
	void append(string name, T)(T t) {
		static if (isArray!T)
		{
			if (t.length == 0)
				return;
		}
		getCollection!(name).insert(t);
		dispatch!(name)("append",t);
	}
	auto readAll(string name, T)() {
		return getCollection!(name).find!T();
	}
	void remove(string name, T)(T t) {
		getCollection!(name).remove(t);
		dispatch!(name)("remove",t);
	}
	void drop(string name)() {
		getCollection!(name).remove();
		dispatch!(name)("remove");
	}
  void dropOld(string name)() {
    db[name].remove();
    dispatch!(name)("remove");
  }
	void update(string name, Selector, Updates)(Selector s, Updates u) {
		getCollection!(name).update(s,u);
		struct Update
		{
			Selector selector;
			Updates updates;
		}
		dispatch!(name)("update",Update(s,u));
	}
	auto find(string name, T, Query)(Query q, int skip = 0, int limit = 0) {
		return getCollection!(name).find!(T,Query)(q,null,QueryFlags.None).skip(skip).limit(limit);
	}
  auto findOld(string name, T)(int skip = 0, int limit = 0) {
    auto cursor = db[name].find!(T).skip(skip);
    if (limit == 0)
      return cursor;
		return cursor.limit(limit);
  }
	auto find(string name, T)(int skip = 0, int limit = 0) {
		auto cursor = getCollection!(name).find!(T).skip(skip);
		if (limit == 0)
			return cursor;
		return cursor.limit(limit);
	}
	bool exists(string name, Query)(Query q) {
		return !getCollection!(name).find(q).empty();
	}
  bool empty(string name)() {
    return getCollection!(name).find().empty();
  }
  bool emptyOld(string name)() {
    return db[name].find().empty();
  }
	void ensureIndex(string name, Fields)(Fields f) {
		return getCollection!(name).ensureIndex(f);
	}
}

@Version(1)
void migrateToVersion1(Persistence db) {
	struct OldDmdVersion {
		@name("_id") string id;
	}
	struct OldDubPackage {
		string _id;
	}
	struct OldJob {
		@name("_id") string id;
		OldDmdVersion dmd;
		OldDubPackage pkg;
	}
	struct OldJobResult {
		OldJob job;
		Timestamp start;
		Timestamp finish;
		string output;
		ErrorStats error;
	}
	int skip = 0;
	do
	{
		auto rawResults = db.findOld!("results",OldJobResult)(skip,24).map!(r=>RawJobResult(r.job.id,r.job.dmd.id,r.job.pkg._id,r.output,r.start,r.finish,r.start)).array();
		if (rawResults.length == 0)
			break;
		db.append!("rawJobResults")(rawResults);
		if (rawResults.length != 24)
			break;
		skip += 24;
	} while (1);
	db.drop!("dmds");
	db.dropOld!("executingJobs");
	db.drop!("jobSets");
	db.drop!("packages");
	db.drop!("jobs");
	db.dropOld!("results");
}

@Version(2)
void migrateToVersion2(Persistence db) {
	db.drop!("dmds");
	db.dropOld!("executingJobs");
	db.drop!("jobSets");
	db.drop!("packages");
	db.drop!("jobs");
	db.dropOld!("results");
}

private template getMigratorVersion(alias T) {
	import std.traits;
	enum getMigratorVersion = getUDAs!(mixin(T),Version)[0].ver;
}
private template sortMigrators(alias T1, alias T2) {
	import std.traits;
	enum sortMigrators = getMigratorVersion!T1 - getMigratorVersion!T2;
}

auto migrator(Persistence db){
  import std.meta;
	struct Migrator{
		private Persistence db;
    template isMigrator(alias T) {
      enum isMigrator = hasUDA!(mixin(T),Version);
    }
    enum migrators = staticSort!(sortMigrators,Filter!(isMigrator,__traits(allMembers, dubster.persistence)));
		this(Persistence db) { this.db = db; }
		bool needsMigration(){
			static if (migrators.length > 0)
				return getMigratorVersion!(migrators[$-1]) > db.config.ver.ver;
			else 
				return false;
		}
		void migrate() {
			auto ver = db.config.ver.ver;
			foreach(migrator; migrators) {
				auto migratorVersion = getMigratorVersion!(migrator);
				if (migratorVersion > ver)
				{
					try {
						logInfo(format("Migrating from %s to version %s...",ver,migratorVersion));
						mixin(migrator ~ "(db);");
						db.config.updateVersion(migratorVersion);
						logInfo(format("Migrated from %s to version %s.",ver,migratorVersion));
					} catch(Exception e)
					{
						throw new Exception(format("Failed to migrate from %s to %s: %s",ver,migratorVersion,e));
					}
				}
			}
		}
	}
	return Migrator(db);
}
