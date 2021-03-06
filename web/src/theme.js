import getMuiTheme from 'material-ui/styles/getMuiTheme';
import {
  blueGrey500, blueGrey700,
  pinkA200,
  grey100, grey300, grey400, grey500,
  white, darkBlack, fullBlack,
} from 'material-ui/styles/colors';
import {fade} from 'material-ui/utils/colorManipulator';

// This replaces the textColor value on the palette
// and then update the keys for each component that depends on it.
// More on Colors: http://www.material-ui.com/#/customization/colors

export default getMuiTheme({
	palette: {
	    primary1Color: blueGrey500,
	    primary2Color: blueGrey700,
	    primary3Color: grey400,
	    accent1Color: pinkA200,
	    accent2Color: grey100,
	    accent3Color: grey500,
	    textColor: darkBlack,
	    secondaryTextColor: fade(darkBlack, 0.54),
	    alternateTextColor: white,
	    canvasColor: white,
	    borderColor: grey300,
	    disabledColor: fade(darkBlack, 0.3),
	    pickerHeaderColor: blueGrey500,
	    clockCircleColor: fade(darkBlack, 0.07),
	    shadowColor: fullBlack,
	  },
	appBar: {
		height: 50,
	},
});