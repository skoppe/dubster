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
import Immutable from 'immutable';
import * as Icons from '../icons.js';
import {
  green700,red900
} from 'material-ui/styles/colors';
import CircularProgress from 'material-ui/CircularProgress';
import SyntaxHighlighter from 'react-syntax-highlighter';
import { tomorrowNight } from 'react-syntax-highlighter/dist/styles';
import bash from 'highlight.js/lib/languages/bash';
import lowlight from 'lowlight/lib/core';
import { Content } from './content.js'

lowlight.registerLanguage('bash', bash)

class Job extends Component {
	constructor(props,context)
	{
		super(props,context);
	}
	componentWillMount(){
		this.props.dispatch(actions.doLoadJob(this.props.routeParams.job))		
	}
	render () {
		let job = this.props.job.get(this.props.routeParams.job);
		if (!job || !job.get("item"))
			return <CircularProgress/>
		let output = job.getIn(["item","output"])
		return (
			<div className="pure-g">
				<div className="pure-u-1">
					<Content>
						<h1>{ job.getIn(["item","job","pkg","name"]) + " " + job.getIn(["item","job","pkg","ver"])}</h1>
						<h3 style={{color:"gray"}}>{ job.getIn(["item","job","dmd","ver"])}</h3>
						<p>{ job.getIn(["item","job","pkg","description"]) }</p>
						<SyntaxHighlighter language='bash' style={tomorrowNight}>{output}</SyntaxHighlighter>
					</Content>
				</div>
			</div>
		)
	}
}
Job.contextTypes = {
	store: storeShape
}
function appConnector(state)
{
	return {job: state.job}
}
export default connect(appConnector,undefined,undefined,{pure:false})(Job);
