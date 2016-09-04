import {default as React, Component} from "react";
import {Link} from "react-router";
import { connect } from 'react-redux'
// import SnackbarQueue from './snackbar-queue.js';
import storeShape from 'react-redux/lib/utils/storeShape'
import {Card, CardText, CardHeader} from 'material-ui/Card';
import * as actions from '../actions.js';
import CircularProgress from 'material-ui/CircularProgress';
import { ProgressIndicator } from './progress.js'

class Dashboard extends Component {
	constructor(props,context)
	{
		super(props,context);
	}
	componentWillMount(){
		this.props.dispatch(actions.doLoadJobSets())
	}
	render () {
		let items = this.props.jobSets.get('data')
		return (
			<div className="pure-g">
				<div className="pure-u-1">
					<h1>JobSets</h1>
				</div>
	    		{
					items.map((jobSet)=>{
						let executingJobs = jobSet.get("executingJobs")
						
						let jobCount = jobSet.get("pendingJobs") + executingJobs + jobSet.get("completedJobs");
						let success = jobSet.get("success")
						let failed = jobSet.get("failed")
						let unknown = jobSet.get("unknown")
						return (
							<div key={jobSet.get("_id")} className="pure-u-1 pure-sm-1 pure-u-md-1-2 pure-u-lg-1-3 pure-u-xl-1-4">
						      <Card>
						      	<Link to={"jobset/"+jobSet.get("_id")}>
								    <CardHeader
								      title={jobSet.get('trigger')}
								      subtitle={jobSet.get('triggerId')}
								      actAsExpander={false}
								      showExpandableButton={false}
								    >{
							    		executingJobs > 0 ? (<CircularProgress size={0.5} style={{float:"right"}}/>) : null
							    	}</CardHeader>
								</Link>
							    <CardText expandable={false}>
									<ProgressIndicator total={jobCount} success={success} failed={failed} unknown={unknown}/>
							    </CardText>
							  </Card>
							</div>
						)
					})
				}
			</div>
		)
	}
}
Dashboard.contextTypes = {
	store: storeShape
}
function appConnector(state)
{
	return {jobSets: state.jobSets}
}
export default connect(appConnector,undefined,undefined,{pure:false})(Dashboard);
