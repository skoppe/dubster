import {default as React, Component} from "react";
import {Link} from "react-router";
import { connect } from 'react-redux'
// import SnackbarQueue from './snackbar-queue.js';
import storeShape from 'react-redux/lib/utils/storeShape'
import {Card, CardActions, CardHeader, CardText} from 'material-ui/Card';
import FlatButton from 'material-ui/FlatButton';
import * as actions from '../actions.js';
import PendingIcon from 'material-ui/svg-icons/action/watch-later';
import BuildIcon from 'material-ui/svg-icons/action/build';
import CompletedIcon from 'material-ui/svg-icons/action/done';
import Badge from 'material-ui/Badge';
import LinearProgress from 'material-ui/LinearProgress';
import {
  lightGreen600,deepOrange700,amber600

} from 'material-ui/styles/colors';
import CircularProgress from 'material-ui/CircularProgress';

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
						let greenSize = jobSet.get("success")*100 / jobCount
						let redSize = jobSet.get("failed")*100 / jobCount
						let graySize = 100 - greenSize - redSize
						let yellowValue = (jobSet.get("unknown")*100 / jobCount) * 100 / graySize
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
							    	<LinearProgress mode="determinate" value={100} color={lightGreen600} style={{borderRadius:"0px",height:"8px",display:"inline-block",width:greenSize+"%"}}/>
							    	<LinearProgress mode="determinate" value={100} color={deepOrange700} style={{borderRadius:"0px",height:"8px",display:"inline-block",width:redSize+"%"}}/>
							    	<LinearProgress mode="determinate" value={yellowValue} color={amber600} style={{borderRadius:"0px",height:"8px",display:"inline-block",width:graySize+"%"}}/>
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
