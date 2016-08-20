(function(){
	var socket

	socket = new WebSocket(getBaseURL() + "/events");
	socket.onopen = function() {
		console.log("connected. waiting for timer...");
	}
	socket.onmessage = function(message) {	
		console.log(message.data);
	}
	socket.onclose = function() {
		console.log("connection closed.");
	}
	socket.onerror = function() {
		console.log("Error!");
	}
	function getBaseURL()
	{
		return  "ws://"+window.location.host;
	}
})();