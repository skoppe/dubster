import {default as React, Component} from "react";
import LinearProgress from 'material-ui/LinearProgress';
import {
  lightGreen,deepOrange,amber
} from './colors.js';
import CircularProgress from 'material-ui/CircularProgress';

export class ProgressIndicator extends Component {
	render () {
		let jobCount = this.props.total;
		let greenSize = this.props.success*100 / jobCount
		let redSize = this.props.failed*100 / jobCount
		let graySize = 100 - greenSize - redSize
		let yellowValue = (this.props.unknown*100 / jobCount) * 100 / graySize
		let size = 4 * (this.props.size || 1)
		return (
			<div>
				<LinearProgress mode="determinate" value={100} color={lightGreen} style={{borderRadius:"0px",height:size+"px",display:"inline-block",width:greenSize+"%"}}/>
				<LinearProgress mode="determinate" value={100} color={deepOrange} style={{borderRadius:"0px",height:size+"px",display:"inline-block",width:redSize+"%"}}/>
				<LinearProgress mode="determinate" value={yellowValue} color={amber} style={{borderRadius:"0px",height:size+"px",display:"inline-block",width:graySize+"%"}}/>
			</div>
		)
	}
}
