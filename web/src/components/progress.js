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
  lightGreen,deepOrange,amber
} from './colors.js';
import CircularProgress from 'material-ui/CircularProgress';

export class ProgressIndicator extends Component {
	render () {
		let jobCount = this.props.pendingJobs + this.props.executingJobs + this.props.completedJobs;
		let greenSize = this.props.success*100 / jobCount
		let redSize = this.props.failed*100 / jobCount
		let graySize = 100 - greenSize - redSize
		let yellowValue = (this.props.unknown*100 / jobCount) * 100 / graySize
		return (
			<div>
				<LinearProgress mode="determinate" value={100} color={lightGreen} style={{borderRadius:"0px",height:"8px",display:"inline-block",width:greenSize+"%"}}/>
				<LinearProgress mode="determinate" value={100} color={deepOrange} style={{borderRadius:"0px",height:"8px",display:"inline-block",width:redSize+"%"}}/>
				<LinearProgress mode="determinate" value={yellowValue} color={amber} style={{borderRadius:"0px",height:"8px",display:"inline-block",width:graySize+"%"}}/>
			</div>
		)
	}
}
