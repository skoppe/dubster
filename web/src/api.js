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
export function searchJobsets(skip,limit = 16)
{
	let query = {skip, limit}
	return get('/jobsets',{query: JSON.stringify(query)});
}
export function dataFeed()
{
	let subject = new Rx.Subject();
	(function(){
		var socket

		socket = new WebSocket("ws"+host.substring(host.indexOf("://"))+"/events")
		socket.onopen = function() {
			subject.onNext({status:{"connected":true}});
		}
		socket.onmessage = function(message) {
			subject.onNext({message})
		}
		socket.onclose = function() {
			subject.onNext({status:{"connected":false}});
		}
		socket.onerror = function() {
			console.log("Error!",arguments);
		}
	})();
	return subject;
}