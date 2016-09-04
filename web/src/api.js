import xhr from 'tiny-xhr'

export function buildUrl(url, query)
{
	if (query == null || query == {})
		return url;
	let keys = Object.keys(query);
	if (keys.length == 0)
		return url;
	return url + "?" + keys.map((key)=>{
		return encodeURIComponent(key)+"="+encodeURIComponent(query[key])
	}).join("&");
}
let token = null;
let host = "https://ghozadab.skoppe.nl"; //document ? document.location.origin : 'http://localhost:8080';
function get(url, params)
{
	return xhr({
		url: buildUrl(host+'/api/v1'+url,params),
		method: 'GET'
	})
}
export function searchJobsets(query)
{
	return get('/jobsets',{query: JSON.stringify(query)});
}
export function getJobsInJobSets(jobSet, skip, limit = 16)
{
	return get('/jobsets/'+jobSet+'/jobs',{skip, limit});
}
export function getJob(id)
{
	return get('/results/'+id);
}
export function getJobSet(id)
{
	return get('/jobsets/'+id)
}
export function getJobSetCompare(frm,to)
{
	return get('/jobsets/'+frm+'/compare/'+to)
}
export function searchPackage(name)
{
	return get('/packages/'+name);
}
export function searchPackages(query)
{
	return get('/packages',{query: JSON.stringify(query)});
}
export function searchPackageVersions(name, skip, limit)
{
	return get('/packages/'+name+'/versions',{skip,limit});
}
export function dataFeed()
{
	return new WebSocket("wss"+host.substring(host.indexOf("://"))+"/events")
}