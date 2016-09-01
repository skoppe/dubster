import Rx from 'rx-lite-dom';

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
	let cnf = 
	{
		method: 'GET',
		responseType: "json",
		cors: true,
		url: buildUrl(host+'/api/v1'+url,params)
	};
	return Rx.DOM.ajax(cnf)
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
export function dataFeed()
{
	let subject = new Rx.Subject();
	var socket = new WebSocket("wss"+host.substring(host.indexOf("://"))+"/events")
	socket.onmessage = function(message) {
		subject.onNext(message)
	}
	socket.onclose = function() {
		subject.onCompleted()
	}
	socket.onerror = function(err) {
		subject.onError(err)
	}
	return subject;
}