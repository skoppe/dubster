import Immutable from 'immutable';

const jobSetsDefault = Immutable.fromJS({
	loaded: 0,
	eof: null,
	status: null,
	errorCode: null,
	errorMessage: null,
	data: []
});
function jobSets(state = jobSetsDefault, action)
{
	switch(action.type)
	{
		case 'QUERY_JOBSETS_START':
			return state.set('status','loading')
		case 'QUERY_JOBSETS_SUCCESS':
			var {status = 'loaded', items, skip, limit} = action.data
			return state
				.set('data',state.get('data').concat(Immutable.fromJS(items)))
				.merge(Immutable.fromJS({status, loaded: skip+limit, eof: items.length != limit}))
		case 'QUERY_JOBSETS_FAILED':
			var {status = 'failed', errorCode, errorMessage} = action.data
			return state.merge(Immutable.fromJS({status,errorCode,errorMessage}))
		case 'JOBSETS_UPDATE':
			var key = state.get('data').findKey(item=>item.get('_id') == action.data.selector._id)
			if (!key)
				return state
			state = state.setIn(['data',key],state.getIn(['data',key]).merge(Immutable.fromJS(action.data.updates.$set)))
			return state
		case 'JOBSETS_APPEND':
			return state.get('data').unshift(action.data).pop()
	}
	return state
}
const jobSetDefault = Immutable.fromJS({
})
function jobSet(state = jobSetDefault, action)
{
	switch(action.type)
	{
		case 'QUERY_JOBS_JOBSET_START':
			var {status = 'loading', id} = action.data
			return state.merge(Immutable.fromJS({[id]:{status}}))
		case 'QUERY_JOBS_JOBSET_SUCCESS':
			var {status = 'loaded', items, id, skip, limit} = action.data
			return state.setIn([id,'items'],state.getIn([id,'items'],Immutable.fromJS([])).concat(Immutable.fromJS(items)))
				.mergeDeep(Immutable.fromJS({[id]:{status,loaded: skip+limit, eof: items.length != limit}}))
		case 'QUERY_JOBS_JOBSET_FAILED':
			var {status = 'failed', errorCode, errorMessage, id} = action.data
			return state.merge(Immutable.fromJS({[id]:{status,errorCode,errorMessage}}))
		case 'QUERY_JOBSET_START':
			return state;
		case 'QUERY_JOBSET_SUCCESS':
			var {status = 'loaded', item, id} = action.data
			return state.setIn([id,'jobset'],Immutable.fromJS({status,item}))
		case 'JOBSETS_UPDATE':
			var jobset = state.get(action.data.selector._id)
			if (!jobset)
				return state
			var item = jobset.getIn(["jobset","item"]);
			if (!item)
				return state
			return state.mergeIn([action.data.selector._id,"jobset","item"],Immutable.fromJS(action.data.updates.$set));
		case 'RESULTS_APPEND':
			action.data.forEach(item=>{
				var id = item.job.jobSet
				var jobset = state.get(id)
				if (!jobset)
					return state
				var items = jobset.get('items')
				if (!items)
					return state
				let {error, finish, job, start} = item
				state = state.setIn([id,'items'],items.unshift(Immutable.fromJS({error, finish, job, start})).pop())
			})
			return state
	}
	return state
}
const jobDefault = Immutable.fromJS({
})
function job(state = jobDefault, action)
{
	switch(action.type)
	{
		case 'QUERY_JOB_START':
			var {status = 'loading', id} = action.data
			return state.merge(Immutable.fromJS({[id]:{status}}))
		case 'QUERY_JOB_SUCCESS':
			var {status = 'loaded', item, id} = action.data
			return state.merge(Immutable.fromJS({[id]:{item,status}}))
		case 'QUERY_JOB_FAILED':
			var {status = 'failed', errorCode, errorMessage, id} = action.data
			return state.merge(Immutable.fromJS({[id]:{status,errorCode,errorMessage}}))
	}
	return state
}
const jobSetsFoundDefault = Immutable.fromJS({
	loaded: 0,
	eof: null,
	status: null,
	errorCode: null,
	errorMessage: null,
	data: [],
	query: {}
});
function jobSetsFound(state = jobSetsFoundDefault, action)
{
	switch(action.type)
	{
		case 'FIND_JOBSET_START':
			return state.set('status','loading')
		case 'FIND_JOBSET_SUCCESS':
			var {status = 'loaded', items, skip, limit, query} = action.data
			return state
				.set('data',state.get('data').concat(Immutable.fromJS(items)))
				.merge(Immutable.fromJS({status, loaded: skip+limit, eof: items.length != limit, query}))
		case 'FIND_JOBSET_FAILED':
			var {status = 'failed', errorCode, errorMessage} = action.data
			return state.merge(Immutable.fromJS({status,errorCode,errorMessage}))
		/* can do update here as well to get latest results
		case 'JOBSETS_UPDATE':
			var key = state.get('data').findKey(item=>item.get('_id') == action.data.selector._id)
			if (!key)
				return state
			state = state.setIn(['data',key],state.getIn(['data',key]).merge(Immutable.fromJS(action.data.updates.$set)))
			return state */
	}
	return state
}
const jobSetsCompareDefault = Immutable.fromJS({
	status: null,
	errorCode: null,
	errorMessage: null,
	items: [],
	to: null,
	from: null
});
function jobSetsCompare(state = jobSetsCompareDefault, action)
{
	switch(action.type)
	{
		case 'LOAD_JOBSET_COMPARE_START':
			return state.set('status','loading')
		case 'LOAD_JOBSET_COMPARE_SUCCESS':
			var {status = 'loaded', items, to, from} = action.data
			return state
				.set('items',state.get('items').concat(Immutable.fromJS(items)))
				.merge(Immutable.fromJS({status, to, from}))
		case 'LOAD_JOBSET_COMPARE_FAILED':
			var {status = 'failed', errorCode, errorMessage} = action.data
			return state.merge(Immutable.fromJS({status,errorCode,errorMessage}))
	}
	return state
}

export default {
	jobSets,
	jobSet,
	job,
	jobSetsFound,
	jobSetsCompare
}