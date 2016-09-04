import {default as React, Component} from "react";
import {Link} from "react-router";
import { connect } from 'react-redux'
import AppBar from 'material-ui/AppBar';
import Drawer from 'material-ui/Drawer';
import MenuItem from 'material-ui/MenuItem';
import storeShape from 'react-redux/lib/utils/storeShape'
import MuiThemeProvider from 'material-ui/styles/MuiThemeProvider';
import theme from '../theme.js'
import * as actions from '../actions.js';

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
						<Link to="/packages" style={{textDecoration:'none'}}><MenuItem onTouchTap={e=>this.handleClose(e)}>Packages</MenuItem></Link>
						<Link to="/" style={{textDecoration:'none'}}><MenuItem onTouchTap={e=>this.handleClose(e)}>JobSets</MenuItem></Link>
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


