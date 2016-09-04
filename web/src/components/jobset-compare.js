import {default as React, Component} from "react";
import {Link} from "react-router";
import { connect } from 'react-redux'
// import SnackbarQueue from './snackbar-queue.js';
import storeShape from 'react-redux/lib/utils/storeShape'
import {Card, CardHeader, CardText} from 'material-ui/Card';
import * as actions from '../actions.js';
import * as Icons from '../icons.js';
import CircularProgress from 'material-ui/CircularProgress';
import { Content } from './content.js'

class JobSetCompare extends Component {
	constructor(props,context)
	{
		super(props,context);
	}
	componentWillMount(){
		this.props.dispatch(actions.doLoadJobSetCompare(this.props.routeParams.from,this.props.routeParams.to))
	}
	render () {
		let frm = this.props.comparison.get('from')
		let to = this.props.comparison.get('to')
		let items = this.props.comparison.get('items')
		if (!frm || !to)
			return <CircularProgress/>
		return (
			<div className="pure-g">
				<div className="pure-u-1-2">
					<Content>
						<h1>{ frm.get("trigger") }</h1>
						<h3 style={{color:"gray"}}>{ frm.get("triggerId") }</h3>
					</Content>
				</div>
				<div className="pure-u-1-2">
					<Content>
						<h1>{ to.get("trigger") }</h1>
						<h3 style={{color:"gray"}}>{ to.get("triggerId") }</h3>
					</Content>
				</div>
				{
					items.map((item,idx) => {
						let frm = item.get('left')
						let to = item.get('right')
						let StatusIconFrom, StatusIconTo;
						let buildErrorFrom = frm.getIn(["error","type"]);
						let buildErrorTo = to.getIn(["error","type"]);
						if (buildErrorFrom == "None")
							StatusIconFrom = Icons.SuccessIcon
						else if (buildErrorFrom == "LinkerError")
							StatusIconFrom = Icons.WarningIcon
						else
							StatusIconFrom = Icons.ErrorIcon
						if (buildErrorTo == "None")
							StatusIconTo = Icons.SuccessIcon
						else if (buildErrorTo == "LinkerError")
							StatusIconTo = Icons.WarningIcon
						else
							StatusIconTo = Icons.ErrorIcon
						return (
							<div key={idx}>
								<div className="pure-u-1-2">
									<Card>
										<Link to={"/jobset/"+this.props.routeParams.from+"/job/"+frm.getIn(["job","_id"])}>
											<CardHeader
												avatar={<StatusIconFrom/>}
												title={" "+frm.getIn(["job","pkg","name"]) + " " + frm.getIn(["job","pkg","ver"])}
												subtitle={frm.getIn(["job","dmd","ver"])}
												actAsExpander={false}
												showExpandableButton={false}
											/>
										</Link>
										<CardText expandable={false}>
											<div>
												Error: { frm.getIn(["error","type"]) }
											</div>
											<div>
												ExitCode: { frm.getIn(["error","exitCode"])}
											</div>
										</CardText>
									</Card>
								</div>
								<div className="pure-u-1-2">
									<Card>
										<Link to={"/jobset/"+this.props.routeParams.to+"/job/"+to.getIn(["job","_id"])}>
											<CardHeader
												avatar={<StatusIconTo/>}
												title={" "+to.getIn(["job","pkg","name"]) + " " + to.getIn(["job","pkg","ver"])}
												subtitle={to.getIn(["job","dmd","ver"])}
												actAsExpander={false}
												showExpandableButton={false}
											/>
										</Link>
										<CardText expandable={false}>
											<div>
												Error: { to.getIn(["error","type"]) }
											</div>
											<div>
												ExitCode: { to.getIn(["error","exitCode"])}
											</div>
										</CardText>
									</Card>
								</div>
							</div>
						)
					})
				}
			</div>
		)
	}
}
JobSetCompare.contextTypes = {
	store: storeShape
}
function appConnector(state)
{
	return {comparison: state.jobSetsCompare}
}
export default connect(appConnector,undefined,undefined,{pure:false})(JobSetCompare);
