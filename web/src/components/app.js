import {default as React, Component} from "react";
import {Link} from "react-router";
import { connect } from 'react-redux'
import AppBar from 'material-ui/AppBar';
import Drawer from 'material-ui/Drawer';
import MenuItem from 'material-ui/MenuItem';
// import SnackbarQueue from './snackbar-queue.js';
import storeShape from 'react-redux/lib/utils/storeShape'
import lightBaseTheme from 'material-ui/styles/baseThemes/lightBaseTheme';
import MuiThemeProvider from 'material-ui/styles/MuiThemeProvider';
import theme from '../theme.js'
import {Card, CardActions, CardHeader, CardText} from 'material-ui/Card';
import FlatButton from 'material-ui/FlatButton';
import * as actions from '../actions.js';
import PendingIcon from 'material-ui/svg-icons/action/watch-later';
import BuildIcon from 'material-ui/svg-icons/action/build';
import CompletedIcon from 'material-ui/svg-icons/action/done';
import Badge from 'material-ui/Badge';

class App extends Component {
	constructor(props,context)
	{
		super(props,context);
		this.state = {open: false}
		this.props.dispatch(actions.doDataFeed())
	}
	handleClose()
	{
		this.setState({open:false});
	}
	handleTouchTap()
	{
		this.props.history.push('/')
	}
	render () {
		let items = this.props.jobSets.get('data')
		return (
			<MuiThemeProvider muiTheme={theme}>
				<div>
					<Drawer docked={false} width={200} open={this.state.open} onRequestChange={open => this.setState({open})}>
						<Link to="podcasts" style={{textDecoration:'none'}}><MenuItem onTouchTap={e=>this.handleClose(e)}>Search Podcasts</MenuItem></Link>
						<Link to="playlists" style={{textDecoration:'none'}}><MenuItem onTouchTap={e=>this.handleClose(e)}>Manage Playlists</MenuItem></Link>
					</Drawer>
					<AppBar	title="Dubster" onTitleTouchTap={_=>this.handleTouchTap()} iconClassNameRight="muidocs-icon-navigation-expand-more" onLeftIconButtonTouchTap={_=> this.setState({open:true})} />
					{this.props.children}
				</div>
			</MuiThemeProvider>
		)
	}
}
App.contextTypes = {
	store: storeShape
}
function appConnector(state)
{
	return {jobSets: state.jobSets}
}
export default connect(appConnector,undefined,undefined,{pure:false})(App);


