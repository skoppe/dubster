import {default as React, Component} from "react";
import {Link} from "react-router";
import { connect } from 'react-redux'
// import SnackbarQueue from './snackbar-queue.js';
import storeShape from 'react-redux/lib/utils/storeShape'
import {Card, CardActions, CardHeader, CardText} from 'material-ui/Card';
import * as actions from '../actions.js';
import * as Icons from '../icons.js';
import { ProgressIndicator } from './progress.js'
import CircularProgress from 'material-ui/CircularProgress';
import { Content } from './content.js'

class Packages extends Component {
	constructor(props,context)
	{
		super(props,context);
		this.state = {openCompare: false}
	}
	componentWillMount(){
		this.props.dispatch(actions.doLoadPackages())
	}
	render () {
		let items = this.props.packages.get('items');
		if (!items)
			return <CircularProgress/>
		return (
			<div className="pure-g">
				<div className="pure-u-1">
					<Content>
						<h1>Packages</h1>
					</Content>
				</div>
				{
					items.map(item=>{

						let success = item.get("success")
						let failed = item.get("failed")
						let unknown = item.get("unknown")
						let totalJobs = success + failed + unknown;
						return (
							<div key={item.getIn(["pkg","name"])} className="pure-u-1 pure-sm-1 pure-u-md-1-2 pure-u-lg-1-3 pure-u-xl-1-4">
								<Card>
									<Link to={"/packages/"+item.getIn(["pkg","name"])}>
										<CardHeader
											title={" "+item.getIn(["pkg","name"])}
											subtitle={item.getIn(["pkg","description"])}
											actAsExpander={false}
											showExpandableButton={false}
										/>
									</Link>
									<CardText expandable={false}>
										<ProgressIndicator total={totalJobs} success={success} failed={failed} unknown={unknown}/>
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
Packages.contextTypes = {
	store: storeShape
}
function appConnector(state)
{
	return {packages: state.packages}
}
export default connect(appConnector,undefined,undefined,{pure:false})(Packages);
