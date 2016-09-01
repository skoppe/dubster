import {default as React, Component} from "react";
import Paper from 'material-ui/Paper';

const style = {
  padding: 20
};

export class Content extends Component {
	render() {
		return (
			<Paper style={style} zDepth={1}>
				{this.props.children}
			</Paper>
		)
	}
}
