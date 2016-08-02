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
import vibe.d;

import dubster.docker;
import dubster.worker;
import dubster.server;
import dubster.reporter;
import dubster.analyser;
import std.stdio : writeln;

void main()
{
	auto settings = readSettings();
	if (!settings.validate())
		return printCommandLineHelp();
	if (!finalizeCommandLineOptions())
		return;

	runTask({
		if (settings.worker)
			new Worker(settings.createWorkerSettings);
		else if (settings.server)
			new Server(settings.createServerSettings, new Persistence(connectMongoDB(settings.mongoHost)), new Reporter());
	});

	runEventLoop();
}
WorkerSettings createWorkerSettings(Settings settings)
{
	return WorkerSettings(
		new RestInterfaceClient!IDubsterApi(settings.serverHost),
		new DockerClient()
	);
}
HTTPServerSettings createServerSettings(Settings settings)
{
	auto sSettings = new HTTPServerSettings();
	sSettings.port = 8080;
	return sSettings;
}
struct Settings
{
	bool worker = false;
	bool server = false;
	bool analyser = false;
	URL serverHost;
	string mongoHost, mongoUser, mongoPass;
}
Settings readSettings()
{
	Settings settings;
	string host;
	if (readOption("worker",&settings.worker,"Starts a worker"))
		if (readOption("serverHost",&host,"Public address of server"))
			settings.serverHost = URL(host);
	if (readOption("server",&settings.server,"Starts a server"))
	{
		readOption("mongoHost",&settings.mongoHost,"MongoDB address");
		readOption("mongoUser",&settings.mongoUser,"MongoDB user");
		readOption("mongoPass",&settings.mongoPass,"MongoDB pass");
	}
	return settings;
}
bool validate(Settings settings)
{
	auto total = cast(int)settings.worker + cast(int)settings.analyser + cast(int)settings.server;
	if (total != 1)
		return false;
	if (settings.worker && settings.serverHost.host.length == 0)
		return false;
	if (settings.server)
	{
		if (settings.mongoHost.length == 0)
			return false;
	}
	return true;
}

// put mongo only on localhost
// only allow data reading through application
// create aggregators that will update stats per package+version / per dmd
	// how should these stats look?
	// per package+version we want to know which dmds are supported
// create simple react viewer with master/detail setup
	// have two tabs "dmd" / "packages"
	// show the different items with the error counts
	// can click on package/dmd name that will show full detail page
	// can click on error count that will jump to filtered detail page
	// detail page will have list of build with controls to filter
// find a way to compare dmd's and get packages that build on one but fail on the other
// 
// 

//What is the absolute minimum here??