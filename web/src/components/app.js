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
import {Tabs, Tab} from 'material-ui/Tabs';
import theme from '../theme.js'
import {Card, CardActions, CardHeader, CardText} from 'material-ui/Card';
import FlatButton from 'material-ui/FlatButton';

class App extends Component {
	constructor(props,context)
	{
		super(props,context);
		this.state = {open: false}
	}
	handleClose()
	{
		this.setState({open:false});
	}
	render () {
		return (
			<MuiThemeProvider muiTheme={theme}>
				<div>
					<Drawer docked={false} width={200} open={this.state.open} onRequestChange={open => this.setState({open})}>
						<Link to="podcasts" style={{textDecoration:'none'}}><MenuItem onTouchTap={e=>this.handleClose(e)}>Search Podcasts</MenuItem></Link>
						<Link to="playlists" style={{textDecoration:'none'}}><MenuItem onTouchTap={e=>this.handleClose(e)}>Manage Playlists</MenuItem></Link>
					</Drawer>
					<AppBar	title="Dubster" iconClassNameRight="muidocs-icon-navigation-expand-more" onLeftIconButtonTouchTap={_=> this.setState({open:true})} />
					<Tabs>
					    <Tab label="Jobsets" >
					    	<div className="pure-g">
								<div className="pure-u-1 pure-sm-1 pure-u-md-1-2 pure-u-lg-1-3 pure-u-xl-1-4">
							      <Card>
								    <CardHeader
								      title="Without Avatar"
								      subtitle="Subtitle"
								      actAsExpander={false}
								      showExpandableButton={false}
								    />
								    <CardActions>
								      <FlatButton label="Action1" />
								      <FlatButton label="Action2" />
								    </CardActions>
								    <CardText expandable={false}>
								      Lorem ipsum dolor sit amet, consectetur adipiscing elit.
								      Donec mattis pretium massa. Aliquam erat volutpat. Nulla facilisi.
								      Donec vulputate interdum sollicitudin. Nunc lacinia auctor quam sed pellentesque.
								      Aliquam dui mauris, mattis quis lacus id, pellentesque lobortis odio.
								    </CardText>
								  </Card>
								</div>
								<div className="pure-u-1 pure-sm-1 pure-u-md-1-2 pure-u-lg-1-3 pure-u-xl-1-4">
							      <Card>
								    <CardHeader
								      title="Without Avatar"
								      subtitle="Subtitle"
								      actAsExpander={false}
								      showExpandableButton={false}
								    />
								    <CardActions>
								      <FlatButton label="Action1" />
								      <FlatButton label="Action2" />
								    </CardActions>
								    <CardText expandable={false}>
								      Lorem ipsum dolor sit amet, consectetur adipiscing elit.
								      Donec mattis pretium massa. Aliquam erat volutpat. Nulla facilisi.
								      Donec vulputate interdum sollicitudin. Nunc lacinia auctor quam sed pellentesque.
								      Aliquam dui mauris, mattis quis lacus id, pellentesque lobortis odio.
								    </CardText>
								  </Card>
								</div>
								<div className="pure-u-1 pure-sm-1 pure-u-md-1-2 pure-u-lg-1-3 pure-u-xl-1-4">
							      <Card>
								    <CardHeader
								      title="Without Avatar"
								      subtitle="Subtitle"
								      actAsExpander={false}
								      showExpandableButton={false}
								    />
								    <CardActions>
								      <FlatButton label="Action1" />
								      <FlatButton label="Action2" />
								    </CardActions>
								    <CardText expandable={false}>
								      Lorem ipsum dolor sit amet, consectetur adipiscing elit.
								      Donec mattis pretium massa. Aliquam erat volutpat. Nulla facilisi.
								      Donec vulputate interdum sollicitudin. Nunc lacinia auctor quam sed pellentesque.
								      Aliquam dui mauris, mattis quis lacus id, pellentesque lobortis odio.
								    </CardText>
								  </Card>
								</div>
								<div className="pure-u-1 pure-sm-1 pure-u-md-1-2 pure-u-lg-1-3 pure-u-xl-1-4">
							      <Card>
								    <CardHeader
								      title="Without Avatar"
								      subtitle="Subtitle"
								      actAsExpander={false}
								      showExpandableButton={false}
								    />
								    <CardActions>
								      <FlatButton label="Action1" />
								      <FlatButton label="Action2" />
								    </CardActions>
								    <CardText expandable={false}>
								      Lorem ipsum dolor sit amet, consectetur adipiscing elit.
								      Donec mattis pretium massa. Aliquam erat volutpat. Nulla facilisi.
								      Donec vulputate interdum sollicitudin. Nunc lacinia auctor quam sed pellentesque.
								      Aliquam dui mauris, mattis quis lacus id, pellentesque lobortis odio.
								    </CardText>
								  </Card>
								</div>
								<div className="pure-u-1 pure-sm-1 pure-u-md-1-2 pure-u-lg-1-3 pure-u-xl-1-4">
							      <Card>
								    <CardHeader
								      title="Without Avatar"
								      subtitle="Subtitle"
								      actAsExpander={false}
								      showExpandableButton={false}
								    />
								    <CardActions>
								      <FlatButton label="Action1" />
								      <FlatButton label="Action2" />
								    </CardActions>
								    <CardText expandable={false}>
								      Lorem ipsum dolor sit amet, consectetur adipiscing elit.
								      Donec mattis pretium massa. Aliquam erat volutpat. Nulla facilisi.
								      Donec vulputate interdum sollicitudin. Nunc lacinia auctor quam sed pellentesque.
								      Aliquam dui mauris, mattis quis lacus id, pellentesque lobortis odio.
								    </CardText>
								  </Card>
								</div>
								<div className="pure-u-1 pure-sm-1 pure-u-md-1-2 pure-u-lg-1-3 pure-u-xl-1-4">
							      <Card>
								    <CardHeader
								      title="Without Avatar"
								      subtitle="Subtitle"
								      actAsExpander={false}
								      showExpandableButton={false}
								    />
								    <CardActions>
								      <FlatButton label="Action1" />
								      <FlatButton label="Action2" />
								    </CardActions>
								    <CardText expandable={false}>
								      Lorem ipsum dolor sit amet, consectetur adipiscing elit.
								      Donec mattis pretium massa. Aliquam erat volutpat. Nulla facilisi.
								      Donec vulputate interdum sollicitudin. Nunc lacinia auctor quam sed pellentesque.
								      Aliquam dui mauris, mattis quis lacus id, pellentesque lobortis odio.
								    </CardText>
								  </Card>
								</div>
							</div>
					    </Tab>
					    <Tab label="Item two" >
					      <div>Bla bla af</div>
					    </Tab>
					</Tabs>
					{this.props.children}
				</div>
			</MuiThemeProvider>
		)
	}
}
				// <SnackbarQueue dispatch={this.props.dispatch} messages={this.props.messages}/>
App.contextTypes = {
	store: storeShape
}
function appConnector(state)
{
	return {messages: state.messages}
}

export default connect(appConnector,undefined,undefined,{pure:false})(App);


