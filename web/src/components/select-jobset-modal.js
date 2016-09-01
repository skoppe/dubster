import React from 'react';
import Dialog from 'material-ui/Dialog';
import FlatButton from 'material-ui/FlatButton';
import RaisedButton from 'material-ui/RaisedButton';
import AutoComplete from 'material-ui/AutoComplete';
import MenuItem from 'material-ui/MenuItem';
import { connect } from 'react-redux'
import storeShape from 'react-redux/lib/utils/storeShape'
import * as actions from '../actions.js';
import { browserHistory } from 'react-router'

export default class SelectJobSetModal extends React.Component {
constructor(props, context) {
    super(props, context);
    this.state = {
      items: []
    }
  }
  componentWillMount(){
    this.props.dispatch(actions.doFindJobSet({types:["DmdRelease"]}))
  }
  handleUpdateInput(value){
    this.props.dispatch(actions.doFindJobSet({query:value,types:["DmdRelease"]}))
  }
  componentWillReceiveProps(nextProps) {
    if (nextProps.jobSets != this.props.jobSets)
    {
      this.state.items = nextProps.jobSets.get("data").map(jobSet => {
        return {
          text: jobSet.get("triggerId"),
          value: (
            <MenuItem
              primaryText={jobSet.get("triggerId")}
              secondaryText={jobSet.get("trigger")}
            />
          ),
          id: jobSet.get("_id")
        }
      }).toJS()
    }
  }
  onSelect(item){
    this.selected = item;
  }
  doCompare(){
    this.props.from
    browserHistory.push('/jobset/'+this.props.from+'/compare/'+this.selected.id)
  }
  render() {
    const actions = [
      <FlatButton
        label="Cancel"
        primary={true}
        onTouchTap={()=>this.props.handleClose()}
      />,
      <FlatButton
        label="Compare"
        primary={true}
        keyboardFocused={true}
        onTouchTap={()=>this.doCompare()}
      />,
    ];

    return (
      <Dialog
        title="Select JobSet to compare with"
        actions={actions}
        modal={false}
        open={this.props.open}
        onRequestClose={this.props.handleClose}
      >
        <AutoComplete
          hintText="Release"
          filter={AutoComplete.noFilter}
          onUpdateInput={(value)=>this.handleUpdateInput(value)}
          onNewRequest={(item)=>this.onSelect(item)}
          openOnFocus={true}
          dataSource={this.state.items}
          fullWidth={true}
        />
      </Dialog>
    );
  }
}
SelectJobSetModal.contextTypes = {
  store: storeShape
}
function appConnector(state)
{
  return {jobSets: state.jobSetsFound}
}
export default connect(appConnector,undefined,undefined,{pure:false})(SelectJobSetModal);