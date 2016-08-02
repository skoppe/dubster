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
module dubster.worker;

import vibe.d;
import dubster.server;
import dubster.job;
import dubster.dmd;
import dubster.dub;
import dubster.docker;
import dubster.reporter;
import dubster.analyser;

enum State
{
	NotAvailable = 1,
	Idle,
	Busy
}
struct WorkerSettings
{
	RestInterfaceClient!IDubsterApi server;
	DockerClient client;
}
Nullable!Job parseJob(Json job)
{
	if (job.type == Json.Type.null_)
		return Nullable!(Job)();
	return Nullable!(Job)(job.deserializeJson!Job);
}
class Worker
{
	State state;
	WorkerSettings settings;
	this(WorkerSettings settings)
	{
		this.settings = settings;
		trigger();
	}
	private void trigger()
	{
		Nullable!Job job = parseJob(settings.server.getJob());
		if (!execute(job))
			setTimer(1.minutes, &this.trigger, false);
		else
			setTimer(1.seconds, &this.trigger, false);
	}
	private bool execute(Nullable!Job job)
	{
		if (job.isNull)
			return false;

		struct Sink
		{
			Appender!string appender;
			void put(T)(T t)
			{
				import std.stdio;
				write(t);
				appender.put(t);
			}
		}
		auto sink = Sink();
		auto compilerPath = settings.client.installCompiler(job.dmd,sink);
		Timestamp start = getTimestamp();
		auto state = settings.client.buildPackage(job.pkg,sink,compilerPath);
		Timestamp end = getTimestamp();
		auto error = sink.appender.data.parseError();
		settings.server.postJobResult(JobResult(job,start,end,sink.appender.data,error));
		return true;
	}
}

