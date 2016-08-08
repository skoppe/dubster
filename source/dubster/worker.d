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

import std.stdio : stdout;

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
	long memoryLimit;
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

		Appender!string appender;
		auto stdoutSink = stdout.lockingTextWriter();
		auto compilerPath = settings.client.installCompiler(job.dmd,stdoutSink);
		Timestamp start = getTimestamp();
		ErrorStats error;
		try
		{
			settings.client.buildPackage(job.pkg,appender,compilerPath,settings.memoryLimit);
			error = appender.data.parseError();
		} catch (TimeoutException e)
		{
			stdoutSink.put(format("Timeout while building % package",job.pkg.name));
			error = ErrorStats(ErrorType.Timeout,1,"");
		}
		Timestamp end = getTimestamp();
		settings.server.postJobResult(JobResult(job,start,end,appender.data,error));
		return true;
	}
}

