import {default as React, Component} from "react";
import {Link} from "react-router";
import { connect } from 'react-redux'
// import SnackbarQueue from './snackbar-queue.js';
import storeShape from 'react-redux/lib/utils/storeShape'
import {Card, CardActions, CardHeader, CardText} from 'material-ui/Card';
import * as actions from '../actions.js';
import PendingIcon from 'material-ui/svg-icons/action/watch-later';
import BuildIcon from 'material-ui/svg-icons/action/build';
import CompletedIcon from 'material-ui/svg-icons/action/done';
import CompareIcon from 'material-ui/svg-icons/action/compare-arrows';
import Badge from 'material-ui/Badge';
import Immutable from 'immutable';
import * as Icons from '../icons.js';
import {
  green700,red900
} from 'material-ui/styles/colors';
import { ProgressIndicator } from './progress.js'
import CircularProgress from 'material-ui/CircularProgress';
import { Content } from './content.js'
import RaisedButton from 'material-ui/RaisedButton';
import FlatButton from 'material-ui/FlatButton';
import SelectJobSetModal from './select-jobset-modal.js';

class JobSet extends Component {
	constructor(props,context)
	{
		super(props,context);
		this.state = {openCompare: false}
	}
	componentWillMount(){
		this.props.dispatch(actions.doLoadJobsInJobSet(this.props.routeParams.jobset))		
		this.props.dispatch(actions.doLoadJobSet(this.props.routeParams.jobset))		
	}
	render () {
		let jobSet = this.props.jobSet.get(this.props.routeParams.jobset)
		if (!jobSet || !jobSet.getIn(["jobset","item"]))
			return <CircularProgress/>

		let item = jobSet.getIn(["jobset","item"])
		let executingJobs = item.get("executingJobs")
		return (
			<div className="pure-g">
				<div className="pure-u-1">
					<Content>
						{
							executingJobs > 0 ? (<CircularProgress size={1.0} style={{float:"right"}}/>) : null
						}
						<h1>{ jobSet.getIn(["jobset","item","trigger"]) }</h1>
						<h3 style={{color:"gray"}}>{ jobSet.getIn(["jobset","item","triggerId"]) }</h3>
						<ProgressIndicator pendingJobs={item.get("pendingJobs")} executingJobs={item.get("executingJobs")} completedJobs={item.get("completedJobs")} success={item.get("success")} failed={item.get("failed")} unknown={item.get("unknown")}/>
						<br/>
						<FlatButton
							label="Compare"
							labelPosition="before"
							primary={true}
							icon={<CompareIcon />}
							onTouchTap={()=>this.setState({openCompare:true})}
						/>
					</Content>
				</div>
				{
					jobSet.get('items',[]).map(item=>{
						let StatusIcon;
						let buildError = item.getIn(["error","type"]);
						let sec = (item.get("finish") - item.get("start")) / 10000000
						if (sec > 60)
						{
							let min = Math.round((sec / 60) - 0.5);
							sec = Math.round(sec - (min * 60))
							var buildTime = `${min} min ${sec} sec`
						} else
						{
							sec = Math.round(sec)
							var buildTime = `${sec} sec`
						}
						let startDate = new Date((item.get("start") / 10000) - 62135596800000)
						if (buildError == "None")
							StatusIcon = Icons.SuccessIcon
						else if (buildError == "LinkerError")
							StatusIcon = Icons.WarningIcon
						else
							StatusIcon = Icons.ErrorIcon
						return (
							<div key={item.getIn(["job","_id"])} className="pure-u-1 pure-sm-1 pure-u-md-1-2 pure-u-lg-1-3 pure-u-xl-1-4">
								<Card>
									<Link to={"/jobset/"+this.props.routeParams.jobset+"/job/"+item.getIn(["job","_id"])}>
										<CardHeader
											avatar={<StatusIcon/>}
											title={" "+item.getIn(["job","pkg","name"]) + " " + item.getIn(["job","pkg","ver"])}
											subtitle={item.getIn(["job","dmd","ver"])}
											actAsExpander={false}
											showExpandableButton={false}
										/>
									</Link>
									<CardText expandable={false}>
										<div>
											Build Time: { buildTime }
										</div>
										<div>
											Error: { item.getIn(["error","type"]) }
										</div>
										<div>
											Start: { startDate.toString() }
										</div>
									</CardText>
								</Card>
							</div>
						)
					})
				}
				<SelectJobSetModal open={this.state.openCompare} handleClose={()=>this.setState({openCompare:false})} from={jobSet.getIn(["jobset","item","_id"])}/>
			</div>
		)
	}
}
JobSet.contextTypes = {
	store: storeShape
}
function appConnector(state)
{
	return {jobSet: state.jobSet}
}
export default connect(appConnector,undefined,undefined,{pure:false})(JobSet);
