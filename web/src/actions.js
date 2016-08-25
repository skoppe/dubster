import * as api from './api.js';

function asyncAction(name, func)
{
	return (dispatch, getState)=>{
		dispatch({ type: name+"_START" });

		let state = getState();
		func(state).subscribe((data)=>{
			dispatch({ type: name+"_SUCCESS", data})
		},(err)=>{
			dispatch({ type: name+"_FAILED", err})
		})
	}
}
export function doLoadJobSets(){
	return asyncAction("QUERY_JOBSETS",function(state){
		let skip = state.jobSets.get('loaded')
		let limit = 16
		return api.searchJobsets(skip,limit).map(r=>{return {items:r.response,skip:skip,limit:limit}})
	})
}
export function doDataFeed(){
	return (dispatch, getState)=>{
		dispatch({type: "DATA_FEED_START"})

		api.dataFeed().subscribe((event)=>{
			console.log(event)
		},(err)=>{
			dispatch({type: "DATA_FEED_FAILED", err})
		})
	}
}