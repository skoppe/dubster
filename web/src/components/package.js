import {default as React, Component} from "react";
import {Link} from "react-router";
import { connect } from 'react-redux'
// import SnackbarQueue from './snackbar-queue.js';
import storeShape from 'react-redux/lib/utils/storeShape'
import {Card, CardActions, CardHeader, CardText} from 'material-ui/Card';
import * as actions from '../actions.js';
import * as Icons from '../icons.js';
import theme from '../theme.js';
import { ProgressIndicator } from './progress.js'
import CircularProgress from 'material-ui/CircularProgress';
import {List, ListItem} from 'material-ui/List';
import Subheader from 'material-ui/Subheader';
import Paper from 'material-ui/Paper';
import {Toolbar, ToolbarGroup, ToolbarTitle} from 'material-ui/Toolbar';
import {OperationFailed} from './operation-failed.js'

const activeStyle = {
	borderLeft:"4px solid "+theme.palette.primary1Color
}

class Package extends Component {
	constructor(props,context)
	{
		super(props,context);
	}
	componentWillMount(){
		this.props.dispatch(actions.doLoadPackage(this.props.routeParams.package))
		this.props.dispatch(actions.doLoadPackageVersions(this.props.routeParams.package))
	}
	render () {
		let pkg = this.props.package.get(this.props.routeParams.package)
		pkg && console.log(pkg.toJS())
		let versions = this.props.packageVersions.get(this.props.routeParams.package)
		versions && console.log(versions.toJS())
		if (pkg && pkg.get('status') == 'failed')
			return <OperationFailed error={pkg.get('error')}/>
		let items = this.props.packageVersions.getIn([this.props.routeParams.package,'items']);
		if (!items)
			return <CircularProgress/>
		let name = this.props.routeParams.package
		return (
			<div>
				<Toolbar>
					<ToolbarGroup>
						<ToolbarTitle text={name} />
					</ToolbarGroup>
				</Toolbar>
				<div className="pure-g">
					<div className="pure-u-1-6 expand">
						<Paper zDepth={1}>
						    <List>
						    	<Subheader>Versions</Subheader>
						    	{
						    		items.map(item=>{
						    			let success = item.get('success'), failed = item.get('failed'), unknown = item.get('unknown');
						    			let total = success+failed+unknown;
						    			return (
											<ListItem key={item.getIn(['pkg','_id'])} style={activeStyle} primaryText={item.getIn(['pkg','ver'])} secondaryText={<ProgressIndicator total={total} success={success} failed={failed} unknown={unknown}/>}/>
						    			)
						    		})
						    	}
						    </List>
						</Paper>
					</div>
				</div>
			</div>
		)
	}
}
Package.contextTypes = {
	store: storeShape
}
function appConnector(state)
{
	return {package: state.package, packageVersions: state.packageVersions}
}
export default connect(appConnector,undefined,undefined,{pure:false})(Package);
