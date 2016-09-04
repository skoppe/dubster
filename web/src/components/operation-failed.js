import {default as React, Component} from "react";
import {Link} from "react-router";
import * as Icons from '../icons.js';
import {Content} from './content.js'
export class OperationFailed extends Component {
	constructor(props,context)
	{
		super(props,context);
	}
	render () {
		return (
			<Content>
				<Icons.ErrorIcon/>
				Error
			</Content>
		)
	}
}
