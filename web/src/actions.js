import * as api from './api.js';

function asyncAction(name, func, data = {})
{
	return (dispatch, getState)=>{
		let state = getState();
		let subject = func(state)
		if (subject)
		{
			dispatch({type: name+"_START", data: data})
			subject.then((data)=>{
				dispatch({ type: name+"_SUCCESS", data})
			},(err)=>{
				dispatch({ type: name+"_FAILED", data, error: {statusCode: err.status}})
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
		return api.searchJobsets({skip,limit}).then(r=>{return {items:r.response,skip:skip,limit:limit}})
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
		return api.getJobsInJobSets(id,skip,limit).then(r=>{return {items:r.response,skip:skip,limit:limit,id}})
	},{id})
}
export function doLoadJobSet(id){
	return asyncAction("QUERY_JOBSET",function(state){
		if (state.jobSet.getIn([id,'jobSet']))
			return
		return api.getJobSet(id).then(r=>{return {item:r.response,id}})
	},{id})
}
export function doDataFeed(){
	return (dispatch, getState)=>{
		dispatch({type: "DATA_FEED_START"})

		var feed = api.dataFeed();
		feed.onmessage = function(message) {
			let {collection, type, data} = JSON.parse(message.data)
			let action = (collection+"_"+type).toUpperCase()
			dispatch({type:action, data})
		}
		feed.onerror = function(err) {
			dispatch({type: "DATA_FEED_FAILED", error: {statusCode: err.status}})
		}
	}
}
export function doLoadJob(id){
	return asyncAction("QUERY_JOB",function(state){
		let loaded = state.job.get(id)
		if (loaded)
			return
		return api.getJob(id).then(r=>{return {id,item:r.response}})
	},{id})
}
export function doFindJobSet(query){
	return asyncAction("FIND_JOBSET",function(state){
		return api.searchJobsets(query).then(r=>{return {items:r.response,query}})
	})
}
export function doLoadJobSetCompare(frm,to){
	return asyncAction("LOAD_JOBSET_COMPARE",function(state){
		return api.getJobSetCompare(frm,to).then(r=>{return r.response})
	})
}
export function doLoadPackages(query = {}){
	query.skip = query.skip || 0;
	query.limit = query.limit || 16;
	return asyncAction("LOAD_PACKAGES",function(state){
		return api.searchPackages(query).then(r=>{return {items:r.response,query}})
	})
}
export function doLoadPackage(name){
	return asyncAction("LOAD_PACKAGE",function(state){
		let cache = state.packages.get('items').find(item=>item.getIn(['pkg','name']) == name)
		if (cache)
			return Promise.resolve({name,item:cache})
		if (state.package.get(name))
			return
		return api.searchPackage(name).then(r=>{return {item:r.response,name}})
	},{name})
}
export function doLoadPackageVersions(name, skip = 0){
	return asyncAction("LOAD_PACKAGE_VERSIONS",function(state){
		let loaded = state.package.getIn([name,'loaded'],0)
		let limit = 16
		if (loaded >= skip+limit)
			return
		limit -= loaded-skip
		skip = Math.max(loaded,skip)
		return api.searchPackageVersions(name,skip,limit).then(r=>{return {items:r.response,skip,limit,name}})
	},{name})
}