import * as api from './api.js';

function asyncAction(name, func, data = {})
{
	return (dispatch, getState)=>{
		let state = getState();
		let subject = func(state)
		if (subject)
		{
			dispatch({type: name+"_START", data: data})
			func(state).subscribe((data)=>{
				dispatch({ type: name+"_SUCCESS", data})
			},(err)=>{
				dispatch({ type: name+"_FAILED", err})
			})
		}
	}
}
export function doLoadJobSets(skip = 0){
	return asyncAction("QUERY_JOBSETS",function(state){
		let loaded = state.jobSets.get('loaded')
		let limit = 16
		if (loaded >= skip+limit)
			return
		limit -= loaded-skip
		skip = Math.max(loaded,skip)
		return api.searchJobsets({skip,limit}).map(r=>{return {items:r.response,skip:skip,limit:limit}})
	})
}
export function doLoadJobsInJobSet(id, skip = 0){
	return asyncAction("QUERY_JOBS_JOBSET",function(state){
		let loaded = state.jobSet.getIn([id,'loaded'],0)
		let limit = 16
		if (loaded >= skip+limit)
			return
		limit -= loaded-skip
		skip = Math.max(loaded,skip)
		return api.getJobsInJobSets(id,skip,limit).map(r=>{return {items:r.response,skip:skip,limit:limit,id}})
	},{id})
}
export function doLoadJobSet(id){
	return asyncAction("QUERY_JOBSET",function(state){
		if (state.jobSet.getIn([id,'jobSet']))
			return
		return api.getJobSet(id).map(r=>{return {item:r.response,id}})
	},{id})
}
export function doDataFeed(){
	return (dispatch, getState)=>{
		dispatch({type: "DATA_FEED_START"})

		api.dataFeed().subscribe((event)=>{
			let {collection, type, data} = JSON.parse(event.data)
			let action = (collection+"_"+type).toUpperCase()
			dispatch({type:action, data})
		},(err)=>{
			dispatch({type: "DATA_FEED_FAILED", err})
		})
	}
}
export function doLoadJob(id){
	return asyncAction("QUERY_JOB",function(state){
		let loaded = state.job.get(id)
		if (loaded)
			return
		return api.getJob(id).map(r=>{return {id,item:r.response}})
	},{id})
}
export function doFindJobSet(query){
	return asyncAction("FIND_JOBSET",function(state){
		return api.searchJobsets(query).map(r=>{return {items:r.response,query}})
	})
}
export function doLoadJobSetCompare(frm,to){
	return asyncAction("LOAD_JOBSET_COMPARE",function(state){
		return api.getJobSetCompare(frm,to).map(r=>{return r.response})
	})
}