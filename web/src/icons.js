import {default as React, Component} from "react";
import CheckCircle from 'material-ui/svg-icons/action/check-circle';
import AlertError from 'material-ui/svg-icons/alert/error';
import {lightGreen, deepOrange, amber} from './components/colors.js';

console.log(lightGreen)

export const SuccessIcon = () => (
  <CheckCircle color={lightGreen}/>
)

export const ErrorIcon = () => (
  <AlertError color={deepOrange}/>
)

export const WarningIcon = () => (
  <AlertError color={amber}/>
)